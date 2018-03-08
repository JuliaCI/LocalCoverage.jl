using LocalCoverage
using Base.Test

@test !isfile("coverage/lcov.info")
generate_coverage("LocalCoverage"; genhtml = false)
@test isfile("coverage/lcov.info")
clean_coverage("LocalCoverage")
@test !isdir("coverage")
