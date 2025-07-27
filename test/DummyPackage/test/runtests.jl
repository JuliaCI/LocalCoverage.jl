using Test, DummyPackage

@test foo() == 42
@test bar() == "a fish"

@testset "testset 1" begin
    @test qux() == 43
end

@testset "testset 2" begin
    @test corge() == "corge"
end

if "testset 3" ∈ ARGS
    @testset "testset 3" begin
            @test 1 == 2
    end
end