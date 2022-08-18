module LocalCoverage

using CoverageTools
using DocStringExtensions
using Printf
using PrettyTables
import Pkg

export generate_coverage, open_coverage, clean_coverage, coverage_summary

"Directory for coverage results."
const COVDIR = "coverage"

"Coverage tracefile."
const LCOVINFO = "lcov.info"

const PYTHON = get!(ENV, "PYTHON", isnothing(Sys.which("python3")) ? "python" : "python3")


struct FileCoverageSummary
    filename::String
    lines_hit::Int
    lines_tracked::Int
    coverage::Float64
    coverage_gaps::Vector{UnitRange{Int}}
end

struct PackageCoverage
    package_dir::String
    files::Vector{FileCoverageSummary}
    lines_hit::Int
    lines_tracked::Int
    coverage::Float64
    target_coverage::Float64
end


"""
$(SIGNATURES)

Get the root directory of a package.
"""
function pkgdir(pkgstr::AbstractString)
    joinpath(dirname(Base.locate_package(Base.PkgId(pkgstr))), "..")
end
pkgdir(m::Module) = joinpath(dirname(pathof(m)), "..")

"""
$(SIGNATURES)

Evaluate the ranges of lines without coverage.
"""
function find_gaps(coverage)
    i = 1
    last_line = length(coverage)
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

"""
$(SIGNATURES)

Open the HTML coverage results in a browser for `pkg` if they exist.

See [`generate_coverage`](@ref).
"""
function open_coverage(pkg;
                       coverage_file::AbstractString=joinpath(COVDIR, "index.html"))
    htmlfile = joinpath(pkgdir(pkg), coverage_file)
    if !isfile(htmlfile)
        @warn("Not found, run generate_coverage(pkg) first.")
        return nothing
    end
    try
        if Sys.isapple()
            run(`open $htmlfile`)
        elseif Sys.islinux() || Sys.isbsd()
            run(`xdg-open $htmlfile`)
        elseif Sys.iswindows()
            run(`start $htmlfile`)
        end
    catch e
        error("Failed to open the generated $(htmlfile)\n",
              "Error: ", sprint(Base.showerror, e))
    end
    nothing
end

"""
$(SIGNATURES)

Returns a table giving coverage details by file in human readable form:
- column 1: source file name
- column 2: tuple (lines_hit, lines_tracked)
- column 3: coverage fraction
"""
function coverage_summary_table(coverage)
    n = length(coverage)
    tab = Array{Any, 2}(undef, 1+n, 3)
    total_hit = 0
    total_tracked    = 0

    for (i, f) in enumerate(coverage)
        hit     = count(x->!isnothing(x) && x>0, f.coverage)
        tracked = count(x->!isnothing(x),        f.coverage)

        total_hit     += hit
        total_tracked += tracked

        tab[i,:] .= (f.filename, (hit, tracked),
                     100 * hit / tracked)
    end

    tab[n+1, :] .= ("TOTAL", (total_hit, total_tracked),
                    100 * total_hit / total_tracked)
    tab
end

"""
$(SIGNATURES)

Pretty-prints a table giving coverage details by file.
"""
function coverage_summary(coverage)
    tab = coverage_summary_table(coverage)

    highlighters = (
        Highlighter((data,i,j)->j==3 && data[i,j] <= 50,
                    bold       = true,
                    foreground = :red),
        Highlighter((data,i,j)->j==3 && data[i,j] <= 70,
                    foreground = :yellow),
        Highlighter((data,i,j)->j==3 && data[i,j] >= 90,
                    foreground = :green),
    )

    formatter(value, i, j) = if j==3
        isnan(value) ? "-" : @sprintf("%3.0f%%", value)
    elseif j==2
        hit, tracked = value
        @sprintf("%3d / %3d", hit, tracked)
    else
        value
    end

    pretty_table(tab,
                 ["File name", "Lines hit", "Coverage"],
                 alignment = [:l, :r, :r],
                 highlighters = highlighters,
                 body_hlines = [size(tab, 1)-1],
                 formatters = formatter)
end

"""
    generate_xml(pkg, filename="cov.xml")

Generate a coverage Cobertura XML in the package `coverage` directory.

This requires the Python package `lcov_cobertura` (>= v2.0.1), available in PyPl via
`pip install lcov_cobertura`.
"""
function generate_xml(pkg, filename="cov.xml")
    run(Cmd(Cmd(["lcov_cobertura", "lcov.info", "-o", filename]),
            dir=joinpath(pkgdir(pkg),COVDIR)))
    @info("generated cobertura XML $filename")
end

"""
$(SIGNATURES)

Generate a coverage report for package `pkg`.

When `genhtml`, the corresponding external command will be called to generate a
HTML report. This can be found in eg the package `lcov` on Debian/Ubuntu.

If `genxml` is true, will generate a Cobertura XML in the `coverage` directory
(requires Python package `lcov_cobertura`, see `generate_xml`).

If `show_summary` is true, a summary will be printed to `stdout`.

`*.cov` files are near the source files as generated by Julia, everything else
is placed in `Pkg.dir(pkg, \"$(COVDIR)\")`. The summary is in
`Pkg.dir(pkg, \"$(COVDIR)\", \"$(LCOVINFO)\")`.

Use [`clean_coverage`](@ref) for cleaning.
"""
function generate_coverage(pkg; genhtml=true, show_summary=true, genxml=false)
    Pkg.test(pkg; coverage = true)
    coverage = cd(pkgdir(pkg)) do
        coverage = CoverageTools.process_folder()
        isdir(COVDIR) || mkdir(COVDIR)
        tracefile = "$(COVDIR)/lcov.info"
        CoverageTools.LCOV.writefile(tracefile, coverage)
        if genhtml
            branch =
                try
                    strip(read(`git rev-parse --abbrev-ref HEAD`, String))
                catch
                    @warn "git branch could not be detected"
                end
            title = "on branch $(branch)"
            try
                run(`genhtml -t $(title) -o $(COVDIR) $(tracefile)`)
            catch e
                error("Failed to run genhtml. Check that lcov is installed (see the README).",
                      "\nError message: ", sprint(Base.showerror, e))
            end
            @info("generated coverage HTML")
        end
        coverage
    end
    genxml && generate_xml(pkg)
    show_summary && coverage_summary(coverage)
    coverage
end

"""
$(SIGNATURES)

Clean up after [`generate_coverage`](@ref).

If `rm_directory`, will delete the coverage directory, otherwise only deletes
`*.cov` coverage output.
"""
function clean_coverage(pkg;
                        coverage_directory::AbstractString=COVDIR,
                        rm_directory::Bool=true)
    CoverageTools.clean_folder(pkgdir(pkg))
    rm_directory && rm(joinpath(pkgdir(pkg), coverage_directory); force = true, recursive = true)
end

end # module
