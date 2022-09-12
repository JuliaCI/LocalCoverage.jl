using LocalCoverage, Test

const pkg = "LocalCoverage"     # we test the package with itself

table_header = r"Filename\s+.\s+Lines\s+.\s+Hit\s+.\s+Miss\s+.\s+%"
table_line = r"(?<!\/|\\\\)src(\/|\\\\)LocalCoverage.jl?\s+.\s+\d+\s+.\s+\d+\s+.\s+\d+\s+.\s+\d+%"
table_footer = r"TOTAL\s+.\s+\d+\s+.\s+\d+\s+.\s+\d+\s+.\s+\d+%"

# prevent infinite recursion when testing
const lockfile = joinpath(tempdir(), "testingLocalCoverage")

covdir = normpath(joinpath(@__DIR__, "..", "coverage"))

if !isfile(lockfile)
    clean_coverage(pkg)

    @test isdir(LocalCoverage.pkgdir(pkg))
    tracefile = joinpath(covdir, "lcov.info")
    @test !isfile(tracefile)
    touch(lockfile)

    cov = generate_coverage(pkg)
    buffer = IOBuffer()
    show(buffer, cov)
    table = String(take!(buffer))
    println(table)
    @test !isnothing(match(table_header, table))
    @test !isnothing(match(table_line, table))
    @test !isnothing(match(table_footer, table))

    if !isnothing(Sys.which("genhtml"))
        mktempdir() do dir
            html_coverage(pkg, dir = dir)
            @test isfile(joinpath(dir, "index.html"))
        end
    end

    rm(lockfile)
    @test isfile(tracefile)
    rm(covdir, recursive = true)

    @test LocalCoverage.find_gaps([nothing, 0, 0, 0, 2, 3, 0, nothing, 0, 3, 0, 6, 2]) ==
        [2:4, 7:7, 9:9, 11:11]

    @info "Printing coverage infomation for visual debugging"
    show(stdout, cov)
    show(IOContext(stdout, :print_gaps => true), cov)
end
