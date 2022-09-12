using LocalCoverage, Test
import Pkg

Pkg.activate("./DummyPackage/")

const pkg = "DummyPackage"      # we test the package with a dummy created for this purpose

table_header = r"Filename\s+.\s+Lines\s+.\s+Hit\s+.\s+Miss\s+.\s+%"
table_line = r"(?<!\/|\\\\)src(\/|\\\\)DummyPackage.jl?\s+.\s+\d+\s+.\s+\d+\s+.\s+\d+\s+.\s+\d+%"
table_footer = r"TOTAL\s+.\s+\d+\s+.\s+\d+\s+.\s+\d+\s+.\s+\d+%"

covdir = normpath(joinpath(@__DIR__, "DummyPackage", "coverage"))

clean_coverage(pkg)
@test isdir(LocalCoverage.pkgdir(pkg))
tracefile = joinpath(covdir, "lcov.info")
@test !isfile(tracefile)

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

@test isfile(tracefile)
rm(covdir, recursive = true)

@info "Printing coverage infomation for visual debugging"
show(stdout, cov)
show(IOContext(stdout, :print_gaps => true), cov)

@test LocalCoverage.find_gaps([nothing, 0, 0, 0, 2, 3, 0, nothing, 0, 3, 0, 6, 2]) ==
    [2:4, 7:7, 9:9, 11:11]
