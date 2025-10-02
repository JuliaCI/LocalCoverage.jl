module LocalCoverage

import CoverageTools
using Coverage: process_folder, process_file
using DocStringExtensions: SIGNATURES, FIELDS
using PrettyTables: PrettyTables, pretty_table
import DefaultApplication
import LibGit2
import Pkg
import Dates
using EzXML
using OrderedCollections

export generate_coverage, process_coverage, clean_coverage, report_coverage_and_exit,
    html_coverage, generate_xml, write_lcov_to_xml

####
#### helper functions and constants
####

"Directory for coverage results."
const COVDIR = "coverage"

"Coverage tracefile."
const LCOVINFO = "lcov.info"

"""
$(SIGNATURES)

Get the root directory of a package. For `nothing`, fall back to the active project.
"""
pkgdir(pkgstr::AbstractString) = abspath(joinpath(dirname(Base.find_package(pkgstr)), ".."))

pkgdir(::Nothing) = dirname(Base.active_project())

####
#### coverage information internals
####

"""
Summarized coverage data about a single file. Evaluated for all files of a package
to compose a [`PackageCoverageSummary`](@ref).

$(FIELDS)
"""
Base.@kwdef struct FileCoverageSummary
    "File path relative to the directory of the project"
    filename::String
    "Number of lines covered by tests"
    lines_hit::Int
    "Number of lines with content to be tested"
    lines_tracked::Int
    "List of all line ranges without coverage"
    coverage_gaps::Vector{UnitRange{Int}}
end

"""
Summarized coverage data about a specific package. Contains a list of
[`FileCoverageSummary`](@ref) relative to the package files as well as global metrics about
the package coverage.

See [`report_coverage_and_exit`](@ref).

$(FIELDS)
"""
Base.@kwdef struct PackageCoverage
    "Absolute path of the package"
    package_dir::String
    "List of files coverage summaries tracked"
    files::Vector{FileCoverageSummary}
    "Total number of lines covered by tests in the package"
    lines_hit::Int
    "Total number of lines with content to be tested in the package"
    lines_tracked::Int
end

function Base.getproperty(summary::Union{PackageCoverage,FileCoverageSummary}, sym::Symbol)
    if sym ≡ :coverage_percentage
        100 * summary.lines_hit / summary.lines_tracked
    else
        getfield(summary, sym)
    end
end

format_gap(gap) = length(gap) == 1 ? "$(first(gap))" : "$(first(gap))–$(last(gap))"

format_gaps(summary::FileCoverageSummary) = join(map(format_gap, summary.coverage_gaps), ", ")

function format_line(summary::Union{PackageCoverage,FileCoverageSummary})
    (; lines_hit, lines_tracked, coverage_percentage) = summary
    is_pkg = summary isa PackageCoverage
    (name = is_pkg ? "TOTAL" : summary.filename,
     total = lines_tracked,
     hit = lines_hit,
     missed = lines_tracked - lines_hit,
     coverage_percentage,
     gaps = is_pkg ? "" : format_gaps(summary))
end

function Base.show(io::IO, summary::PackageCoverage)
    (; files, package_dir) = summary
    row_data = map(format_line, files)
    push!(row_data, format_line(summary))
    row_coverage = map(x -> x.coverage_percentage, row_data)
    rows = map(row_data) do row
        (; name, total, hit, missed, coverage_percentage, gaps) = row
        percentage = isnan(coverage_percentage) ? "-" : "$(round(Int, coverage_percentage))%"
        (; name, total, hit, missed, percentage, gaps)
    end
    header = ["Filename", "Lines", "Hit", "Miss", "%"]
    percentage_column = length(header)
    alignment = [:l, :r, :r, :r, :r]
    columns_width = fill(-1, 5) # We need strictly negative number to autosize in PrettyTables 3.0, but this also works in v2
    if get(io, :print_gaps, false)
        push!(header, "Gaps")
        push!(alignment, :l)
        display_cols = last(get(io, :displaysize, 100))
        push!(columns_width, display_cols - 45)
    else
        rows = map(row -> Base.structdiff(row, NamedTuple{(:gaps,)}), rows)
    end
    # PrettyTables 3.0 changed Highlighter to TextHighlighter, which up to currently published version (v3.10) does not provide the kwargs constructor (despite having it documented). We create here a patch to handle both cases
    Highlighter(f; kwargs...) = @static if pkgversion(PrettyTables) < v"3.0.0"
        PrettyTables.Highlighter(f; kwargs...)
    else
        PrettyTables.TextHighlighter(f, PrettyTables.Crayon(;kwargs...))
    end

    highlighters = (
        Highlighter(
            (data, i, j) -> j == percentage_column && row_coverage[i] <= 50,
            bold = true,
            foreground = :red,
        ),
        Highlighter((data, i, j) -> j == percentage_column && row_coverage[i] <= 70,
                    foreground = :yellow),
        Highlighter((data, i, j) -> j == percentage_column && row_coverage[i] >= 90,
                    foreground = :green),
    )

    # Kwargs of `pretty_table` itself also changed in PrettyTables 3.0, so we have to branch here as well
    @static if pkgversion(PrettyTables) < v"3.0.0"
        pretty_table(
            io,
            rows;
            title = "Coverage of $(package_dir)",
            header,
            alignment,
            crop = :none,
            linebreaks = true,
            columns_width,
            autowrap = true,
            highlighters,
            body_hlines = [length(rows) - 1],
        )
    else
        pretty_table(
            io,
            rows;
            title = "Coverage of $(package_dir)",
            column_labels = [header],
            alignment,
            # The crop kwarg is not present anymore, split into the next two ones
            fit_table_in_display_horizontally = false,
            fit_table_in_display_vertically = false,
            line_breaks = true,
            fixed_data_column_widths = columns_width,
            auto_wrap = true,
            highlighters = collect(highlighters), # v3 expects a vector instead of a Tuple
            table_format = PrettyTables.TextTableFormat(;
                horizontal_lines_at_data_rows = [length(rows) - 1],
            ),
        )
    end
end

"""
$(SIGNATURES)

Evaluate the ranges of lines without coverage.

`coverage` is the vector of coverage counts for each line.
"""
function find_gaps(coverage)
    i, last_line = firstindex(coverage), lastindex(coverage)
    gaps = UnitRange{Int}[]
    while i < last_line
        gap_start = i = findnext(x -> !isnothing(x) && iszero(x), coverage, i)
        isnothing(gap_start) && break
        gap_end =
            i = something(
                findnext(x -> isnothing(x) || !iszero(x), coverage, i),
                last_line + 1,
            )
        push!(gaps, gap_start:(gap_end-1))
    end
    gaps
end

####
#### API
####

"""
$(SIGNATURES)

Evaluate the coverage metrics for the given pkg.
"""
function eval_coverage_metrics(coverage, package_dir)::PackageCoverage
    files = map(coverage) do file
        (; coverage) = file
        lines_tracked = count(!isnothing, coverage)
        coverage_gaps = find_gaps(coverage)
        lines_hit = lines_tracked - sum(length, coverage_gaps; init = 0)
        filename = relpath(file.filename, package_dir)
        FileCoverageSummary(; filename, lines_hit, lines_tracked, coverage_gaps)
    end
    lines_hit = sum(x -> x.lines_hit, files; init = 0)
    lines_tracked = sum(x -> x.lines_tracked, files; init = 0)
    PackageCoverage(; package_dir, files, lines_hit, lines_tracked)
end

"""
$(SIGNATURES)

Generate a summary of coverage results for package `pkg`.

If no `pkg` is supplied, the method operates in the currently active package.

# Keyword arguments (and their defaults)

- `run_test = true` determines whether tests are executed. When `false`, test execution
step is skipped allowing an easier use in combination with other test packages.

- `test_args = [""]` is passed on to `Pkg.test`.

- `folder_list = ["src"]` and `file_list = []` are combined for coverage information. If
a test is run on files/folders that *are not* in the list, then those files will be
shown as having 0% coverage.

Coverage of subsets of tests/files can be generated by specifying the list of testsets
to run along with corresponding lists of files/folders.

An lcov file is also produced in `Pkg.dir(pkg, \"$(COVDIR)\", \"$(LCOVINFO)\")`.

See [`report_coverage_and_exit`](@ref), [`clean_coverage`](@ref).

# Error handling

If tests error, the coverage summary is still printed, then the error is rethrown.

# Printing

Printing of the result can be controlled via `IOContext`. See the keyword arguments of
[`report_coverage_and_exit`](@ref). Example:

```julia
cov = generate_coverage(pkg)
show(IOContext(stdout, :print_gaps => true), cov) # print coverage gap information
```
"""
function generate_coverage(pkg = nothing;
                           run_test = true,
                           test_args = [""],
                           folder_list = ["src"],
                           file_list = [])::PackageCoverage

    try
        if run_test
            if isnothing(pkg)
                Pkg.test(; coverage = true, test_args = test_args)
            else
                Pkg.test(pkg; coverage = true, test_args = test_args)
            end
        end
    catch e
        coverage = process_coverage(pkg; folder_list, file_list)
        println(stdout, coverage)
        rethrow(e)
    end
    return process_coverage(pkg; folder_list, file_list)
end

"""
$(SIGNATURES)

Process coverage files.

`pkg` is a string specifying the package, `nothing` (the default) will use the package
that corresponds to the active project.

The keyword arguments `folder_list` and `file_list` should be vectors of strings,
specifying relative paths (eg `"src"`) within the package.

Note: this function is called by [`generate_coverage`](@ref) automatically.
"""
function process_coverage(pkg::Union{Nothing,AbstractString}=nothing;
                          folder_list=["src"],
                          file_list=[])::PackageCoverage
    package_dir = pkgdir(pkg)
    cd(package_dir) do
        # initialize empty vector of coverage data
        coverage = Vector{CoverageTools.FileCoverage}()
        # process folders (same as default if `folder_list` isn't provided)
        for f in folder_list
            append!(coverage, process_folder(f))
        end
        # process individual files
        for f in file_list
            push!(coverage, process_file(f))
        end
        mkpath(COVDIR)
        tracefile = joinpath(COVDIR, LCOVINFO)
        CoverageTools.LCOV.writefile(tracefile, coverage)
        CoverageTools.clean_folder(package_dir)
        eval_coverage_metrics(coverage, package_dir)
    end
end

"""
$(SIGNATURES)

Clean up after [`generate_coverage`](@ref).

If `rm_directory`, will delete the coverage directory, otherwise only deletes the
`$(LCOVINFO) file.
"""
function clean_coverage(pkg = nothing; rm_directory::Bool = true)
    cd(pkgdir(pkg)) do
        if rm_directory
            rm(COVDIR; force = true, recursive = true)
        else
            rm(joinpath(COVDIR, LCOVINFO))
        end
    end
end

"""
$(SIGNATURES)

Generate, and optionally open, the HTML coverage summary in a browser
for `pkg` inside `dir`. The optional keyword argument `css` can be
used to set the path to a custom CSS file styling the coverage report.

See [`generate_coverage`](@ref).
"""
function html_coverage(coverage::PackageCoverage; gitroot = ".", open = false, dir = tempdir(),
                       css::Union{Nothing,AbstractString} = nothing)
    cd(coverage.package_dir) do
        branch = try
            LibGit2.headname(LibGit2.GitRepo(gitroot))
        catch
            @warn "git branch could not be detected, pass the `gitroot` kwarg if the git root is not the same as the package directory."
        end

        title = "on branch $(branch)"
        tracefile = joinpath(COVDIR, LCOVINFO)

        try
            cmd = `genhtml -t $(title) -o $(dir) $(tracefile)`
            if !isnothing(css)
                css_file = abspath(css)
                isfile(css_file) || throw(ArgumentError("Could not find CSS file at $(css_file)"))
                cmd = `$(cmd) --css-file $(css_file)`
            end
            run(cmd)
        catch e
            error(
                "Failed to run genhtml. Check that lcov is installed (see the README).",
                "\nError message: ",
                sprint(Base.showerror, e),
            )
        end
        @info("generated coverage HTML $(joinpath(dir, "index.html")).")
        open && DefaultApplication.open(joinpath(dir, "index.html"))
    end
    nothing
end

function html_coverage(pkg = nothing;
                       gitroot = ".",
                       open = false,
                       dir = tempdir(),
                       test_args = [""],
                       folder_list = ["src"],
                       file_list = [],
                       css = nothing)
    gen_cov() = generate_coverage(pkg; test_args = test_args, folder_list = folder_list, file_list = file_list)
    html_coverage(gen_cov(); gitroot = gitroot, open = open, dir = dir, css = css)
end

"""
$(SIGNATURES)

Utility method that prints coverage statistics and exits with a status code 0 if
the target coverage was met or with a status code 1 otherwise. Useful in command
line, e.g.

```bash
julia --project=@. -e'using LocalCoverage; report_coverage_and_exit(;target_coverage=90)'
```

# Arguments

The only positional argument is either information generated by [`generate_coverage`](@ref),
or a package name (defaults to `nothing`, the active project). For the latter, coverage will
be generated.

# Keyword arguments and defaults

- `target_coverage = 80` determines the threshold for passing coverage
- `print_summary = true` controls whether a detailed summary is printed
- `print_gaps = false` controls whether gaps are printed
- `io` can be used for redirecting the output
"""
function report_coverage_and_exit(coverage::PackageCoverage;
                                  target_coverage::Real = 80,
                                  print_summary::Bool = true,
                                  print_gaps::Bool = false,
                                  io::IO = stdout)
    was_target_met = coverage.coverage_percentage >= target_coverage
    print_summary && show(IOContext(io, :print_gaps => print_gaps), coverage)
    print(io, " Target coverage ", was_target_met ? "was met" : "wasn't met", " (")
    printstyled(io, "$target_coverage%", color = was_target_met ? :green : :red, bold = true)
    println(io, ")")
    exit(was_target_met ? 0 : 1)
end

function report_coverage_and_exit(pkg = nothing;
                                  test_args = [""],
                                  folder_list = ["src"],
                                  file_list = [],
                                  kwargs...)
    coverage = generate_coverage(pkg; test_args = test_args, folder_list = folder_list, file_list = file_list)
    report_coverage_and_exit(coverage; kwargs...)
end

"""
$(SIGNATURES)

Generate a coverage Cobertura XML in the package `coverage` directory.

This requires the Python package `lcov_cobertura` (>= v2.0.1), available in PyPl via
`pip install lcov_cobertura`.
"""
function generate_xml(coverage::PackageCoverage, filename="cov.xml")
    run(Cmd(Cmd(["lcov_cobertura", "lcov.info", "-o", filename]),
            dir = joinpath(coverage.package_dir, COVDIR)))
    @info("generated cobertura XML $(joinpath(coverage.package_dir, COVDIR, filename)).")
end

"""
$(SIGNATURES)

Convert a LCOV coverage file to a Cobertura coverage file. Relies on EzXML
"""
function write_lcov_to_xml(xmlpath::AbstractString, lcovpath::AbstractString;base_dir="."::AbstractString)
    lcov = LcovParser(lcovpath,base_dir)
    xmlcoverage = lcov_to_xml(lcov)
    open(xmlpath, "w") do io
        prettyprint(io, xmlcoverage)
    end
end

"""
Property container for LCOV -> Cobertura conversion.
For internal use only.

$(FIELDS)
"""
struct LcovParser
    "LCOV file path"
    lcov_file::String
    "Base directory for path"
    base_dir::String
end

"""
$(SIGNATURES)

Convert a LCOV file to a nested dictionary structure ready for XML conversion
"""
function lcov_parse(lcov::LcovParser; timestamp = round(Int, Dates.datetime2unix(Dates.now())))
    coverage_data = OrderedDict(
        "packages" => OrderedDict{String,Any}(),
        "summary" => OrderedDict(
            "lines-total" => 0,
            "lines-covered" => 0,
            "branches-total" => 0,
            "branches-covered" => 0
        ),
        "timestamp" => timestamp
    )
    package = nothing
    current_file = nothing
    file_lines_total = 0
    file_lines_covered = 0
    file_lines = OrderedDict()
    file_methods = OrderedDict()
    file_branches_total = 0
    file_branches_covered = 0

    for line in eachline(lcov.lcov_file)
        if strip(line) == "end_of_record"
            if !isnothing(current_file)
                package_dict = coverage_data["packages"][package]
                package_dict["lines-total"] += file_lines_total
                package_dict["lines-covered"] += file_lines_covered
                package_dict["branches-total"] += file_branches_total
                package_dict["branches-covered"] += file_branches_covered
                file_dict = package_dict["classes"][current_file]
                file_dict["lines-total"] = file_lines_total
                file_dict["lines-covered"] = file_lines_covered
                file_dict["lines"] = deepcopy(file_lines)
                file_dict["methods"] = deepcopy(file_methods)
                file_dict["branches-total"] = file_branches_total
                file_dict["branches-covered"] = file_branches_covered
                coverage_data["summary"]["lines-total"] += file_lines_total
                coverage_data["summary"]["lines-covered"] += file_lines_covered
                coverage_data["summary"]["branches-total"] += file_branches_total
                coverage_data["summary"]["branches-covered"] += file_branches_covered
            end
        end
        line_parts = split(line, ":", limit=2)
        input_type = first(line_parts)
        if input_type == "SF"
            # Get file name
            file_name = strip(last(line_parts))
            relative_file_name = relpath(file_name, lcov.base_dir)
            package = join(splitpath(relative_file_name)[1:end-1], '.')
            class_name = join(splitpath(relative_file_name), '.')
            if !(package in keys(coverage_data["packages"]))
                coverage_data["packages"][package] = OrderedDict(
                    "classes" => OrderedDict(),
                    "lines-total" => 0,
                    "lines-covered" => 0,
                    "branches-total" => 0,
                    "branches-covered" => 0
                )
            end
            coverage_data["packages"][package]["classes"][relative_file_name] = OrderedDict(
                "name" => class_name,
                "lines" => OrderedDict(),
                "lines-total" => 0,
                "lines-covered" => 0,
                "branches-total" => 0,
                "branches-covered" => 0
            )
            package = package
            current_file = relative_file_name
            file_lines_total = 0
            file_lines_covered = 0
            empty!(file_lines)
            empty!(file_methods)
            file_branches_total = 0
            file_branches_covered = 0
        elseif input_type == "DA"
            # DA:2,0
            (line_number, line_hits) = split(strip(last(line_parts)), ",")[1:2]
            if !(line_number in keys(file_lines))
                file_lines[line_number] = OrderedDict(
                    "branch" => "false",
                    "branches-total" => 0,
                    "branches-covered" => 0
                )
                file_lines[line_number]["hits"] = line_hits
                # Increment lines total/covered for class and package
                if tryparse(Int64, line_hits) > 0
                    file_lines_covered += 1
                end
                file_lines_total += 1
            elseif input_type == "BRDA"
                # BRDA:1,1,2,0
                (line_number, block_number, branch_number, branch_hits) = split(strip(last(line_parts)), ",")
                if !(line_number in keys(file_lines))
                    file_lines[line_number] = OrderedDict(
                        "branch" => "true",
                        "branches-total" => 0,
                        "branches-covered" => 0,
                        "hits" => 0
                    )
                end
                file_lines[line_number]["branch"] = "true"
                file_lines[line_number]["branches-total"] += 1
                file_branches_total += 1
                if branch_hits != "-" && branch_hits > 0
                    file_lines[line_number]["branches-covered"] += 1
                    file_branches_covered += 1
                end
            elseif input_type == "BRF"
                file_branches_total = first(line_parts)
            elseif input_type == "BRH"
                file_branches_covered = first(line_parts)
            elseif input_type == "FN"
                # FN:5,(anonymous_1)
                function_line, function_name = split(strip(last(line_parts)); limit=2)
                file_methods[function_name] = [function_line, "0"]
            elseif input_type == "FNDA"
                # FNDA:0,(anonymous_1)
                (function_hits, function_name) = split(strip(last(line_parts)); limit=2)
                if !(function_name in file_methods)
                    file_methods[function_name] = ["0", "0"]
                    file_methods[function_name][end] = function_hits
                end
            end
        end

        # Compute line coverage rates
        for package_data in values(coverage_data["packages"])
            package_data["line-rate"] = _percent(package_data["lines-total"], package_data["lines-covered"])
            package_data["branch-rate"] = _percent(package_data["branches-total"], package_data["branches-covered"])
        end
    end
    return coverage_data
end


"""
$(SIGNATURES)

Convert lcov file to cobertura XML using options from this instance.
"""
function lcov_to_xml(lcov::LcovParser)
    coverage_data = lcov_parse(lcov)
    return generate_cobertura_xml(lcov, coverage_data)
end


"""
$(SIGNATURES)

Given parsed coverage data, return a String cobertura XML representation.
"""
function generate_cobertura_xml(lcov::LcovParser, coverage_data)
    document = EzXML.XMLDocument()
    root = ElementNode("coverage")
    setroot!(document, root)
    dtd = DTDNode("coverage","http://cobertura.sourceforge.net/xml/coverage-04.dtd")
    setdtd!(document,dtd)

    summary = coverage_data["summary"]
    root["branch-rate"] = _percent(summary["branches-total"], summary["branches-covered"])
    root["branches-covered"] = string(summary["branches-covered"])
    root["branches-valid"] = string(summary["branches-total"])
    root["complexity"] = "0"
    root["line-rate"] = _percent(summary["lines-total"], summary["lines-covered"])
    root["lines-covered"] = string(summary["lines-covered"])
    root["lines-valid"] = string(summary["lines-total"])
    root["timestamp"] = coverage_data["timestamp"]
    root["version"] = "2.0.3"


    sources = ElementNode("sources")
    link!(root, sources)

    source = ElementNode("source")
    link!(sources, source)
    link!(source, TextNode(lcov.base_dir))


    packages_el = ElementNode("packages")

    packages = coverage_data["packages"]
    for (package_name, package_data) in packages
        package_el = ElementNode("package")
        package_el["line-rate"] = package_data["line-rate"]
        package_el["branch-rate"] = package_data["branch-rate"]
        package_el["name"] = package_name
        package_el["complexity"] = "0"

        classes_el = ElementNode("classes")
        for (class_name, class_data) in package_data["classes"]
            class_el = ElementNode("class")
            class_el["branch-rate"] = _percent(class_data["branches-total"], class_data["branches-covered"])
            class_el["complexity"] = "0"
            class_el["filename"] = class_name
            class_el["line-rate"] = _percent(class_data["lines-total"], class_data["lines-covered"])
            class_el["name"] = class_data["name"]
            # link!(classes_el, class_el)
            # Process methods
            methods_el = ElementNode("methods")
            for (method_name, (line, hits)) in class_data["methods"]
                method_el = ElementNode("method")
                method_el["name"] = method_name
                method_el["signature"] = ""
                method_el["line-rate"] = hits > 0 ? "1.0" : "0.0"
                method_el["branch-rate"] = hits > 0 ? "1.0" : "0.0"

                method_lines_el = ElementNode("lines")
                method_line_el = ElementNode("line")
                method_line_el["hits"] = hits
                method_line_el["number"] = line
                method_line_el["branch"] = "false"

                link!(method_lines_el, method_line_el)
                link!(method_el, method_lines_el)
                link!(methods_el, method_el)
            end
            # Process lines
            lines_el = ElementNode("lines")
            lines = keys(class_data["lines"])
            for line_number in lines
                line_el = ElementNode("line")
                line_el["branch"] = class_data["lines"][line_number]["branch"]
                line_el["hits"] = string(class_data["lines"][line_number]["hits"])
                line_el["number"] = string(line_number)

                if class_data["lines"][line_number]["branch"] == "true"
                    total = class_data["lines"][line_number]["branches-total"]
                    covered = class_data["lines"][line_number]["branches-covered"]
                    percentage = (covered * 100.0) / total
                    line_el["condition-coverage"] = "$percentage % ($covered/$total)"
                end
                link!(lines_el, line_el)
            end
            link!(class_el, methods_el)
            link!(class_el, lines_el)
            link!(classes_el, class_el)
        end
        link!(package_el, classes_el)
        link!(packages_el, package_el)
    end
    link!(root, packages_el)

    return document

end

"""
$(SIGNATURES)

Get the percentage of lines covered in the total, with formatting
"""
_percent(lines_total::Integer, lines_covered::Integer) = lines_total == 0 ? "0.0" : string(lines_covered / lines_total)




end # module
