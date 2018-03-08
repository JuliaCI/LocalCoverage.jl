using LocalCoverage
using Base.Test

lockfile = "/tmp/testingLocalCoverage" # prevent infinite recursion with Pkg.test

if !isfile(lockfile)
    @test !isfile("coverage/lcov.info")
    touch(lockfile)
    generate_coverage("LocalCoverage"; genhtml = false)
    rm(lockfile)
    @test isfile("coverage/lcov.info")
    clean_coverage("LocalCoverage")
    @test !isdir("coverage")
end
