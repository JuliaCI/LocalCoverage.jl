using LocalCoverage, Test

lockfile = "/tmp/testingLocalCoverage" # prevent infinite recursion when testing

covdir = normpath(joinpath(@__DIR__, "..", "coverage"))

if !isfile(lockfile)
    @test isdir(LocalCoverage.pkgdir("LocalCoverage"))
    tracefile = joinpath(covdir, "lcov.info")
    @test !isfile(tracefile)
    touch(lockfile)
    cov = generate_coverage("LocalCoverage"; genhtml=true, show_summary=false)
    tab = LocalCoverage.coverage_summary_table(cov)
    @test tab[1,1] == "src/LocalCoverage.jl"
    LocalCoverage.coverage_summary(cov)
    rm(lockfile)
    @test isfile(tracefile)
    clean_coverage("LocalCoverage", rm_directory=true)
    @test !isdir(covdir)
end
