"A package for testing coverage generation."
module DummyPackage

export foo, bar, baz, qux, quux, corge, grault

foo() = 42

include("bar.jl")
include("qux.jl")
include("corge/grault.jl")
include("corge/corge.jl")

end
