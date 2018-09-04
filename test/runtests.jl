using LocalCoverage, Test

lockfile = "/tmp/testingLocalCoverage" # prevent infinite recursion when testing

covdir = normpath(joinpath(@__DIR__, "..", "coverage"))

if !isfile(lockfile)
    tracefile = joinpath(covdir, "lcov.info")
    @test !isfile(tracefile)
    touch(lockfile)
    generate_coverage("LocalCoverage"; genhtml = false)
    rm(lockfile)
    @test isfile(tracefile)
    clean_coverage("LocalCoverage")
    @test !isdir(covdir)
end
