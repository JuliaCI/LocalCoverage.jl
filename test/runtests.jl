using LocalCoverage
using Compat.Test

lockfile = "/tmp/testingLocalCoverage" # prevent infinite recursion with Pkg.test

if !isfile(lockfile)
    covdir = Pkg.dir("LocalCoverage", "coverage")
    tracefile = joinpath(covdir, "lcov.info")
    @test !isfile(tracefile)
    touch(lockfile)
    generate_coverage("LocalCoverage"; genhtml = false)
    rm(lockfile)
    @test isfile(tracefile)
    clean_coverage("LocalCoverage")
    @test !isdir(covdir)
end
