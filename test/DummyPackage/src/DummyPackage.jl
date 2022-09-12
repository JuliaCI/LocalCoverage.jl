"A package for testing coverage generation."
module DummyPackage

export foo, bar

foo() = 42

include("bar.jl")

end
