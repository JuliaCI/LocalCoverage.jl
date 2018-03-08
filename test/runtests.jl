using LocalCoverage
using Base.Test

@testset "coverage generation and cleanup" begin
    @test !isfile("coverage/lcov.info")
    generate_coverage("LocalCoverage"; genhtml = false)
    @test isfile("coverage/lcov.info")
    clean_coverage("LocalCoverage")
    @test !isdir("coverage")
end
