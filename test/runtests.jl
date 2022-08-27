using LocalCoverage, Test

table_header = r"File name\s+.\s+Lines hit\s+.\s+Coverage\s+.\s+Missing"
table_line = r"src(\/|\\\\)LocalCoverage.jl?\s+.\s+\d+\s*\/\s*\d+\s+.\s+\d+%\s+.\s+"
table_footer = r"TOTAL\s+.\s+\d+\s*\/\s*\d+\s+.\s+\d+%\s+.\s+."

lockfile = joinpath(tempdir(), "testingLocalCoverage") # prevent infinite recursion when testing

covdir = normpath(joinpath(@__DIR__, "..", "coverage"))

if !isfile(lockfile)
    @test isdir(LocalCoverage.pkgdir("LocalCoverage"))
    tracefile = joinpath(covdir, "lcov.info")
    @test !isfile(tracefile)
    touch(lockfile)

    cov = generate_coverage("LocalCoverage")
    buffer = IOBuffer()
    show(buffer, cov)
    table = String(take!(buffer))
    @test !isnothing(match(table_header, table))
    @test !isnothing(match(table_line, table))
    @test !isnothing(match(table_footer, table))

    mktempdir() do dir
        html_coverage("LocalCoverage", dir = dir)
        @test isfile(joinpath(dir, "index.html"))
    end

    rm(lockfile)
    @test isfile(tracefile)
    rm(covdir, recursive = true)

    @test LocalCoverage.find_gaps([nothing, 0, 0, 0, 2, 3, 0, nothing, 0, 3, 0, 6, 2]) ==
          [2:4, 7:7, 9:9, 11:11]
end
