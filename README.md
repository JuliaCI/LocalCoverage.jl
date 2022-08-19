# LocalCoverage.jl

![lifecycle](https://img.shields.io/badge/lifecycle-maturing-blue.svg)
[![build](https://github.com/JuliaCI/LocalCoverage.jl/workflows/CI/badge.svg)](https://github.com/JuliaCI/LocalCoverage.jl/actions?query=workflow%3ACI)
[![codecov.io](http://codecov.io/github/JuliaCI/LocalCoverage.jl/coverage.svg?branch=master)](http://codecov.io/github/JuliaCI/LocalCoverage.jl?branch=master)

This is a collection of trivial functions to facilitate generating and exploring test coverage information for Julia packages *locally*, without using any remote/cloud services.

## Installation

```julia
Pkg.add("LocalCoverage")
```
or `]add LocalCoverage` from the Julia REPL.

### Optional Dependencies
The package has several optional features which require additional dependencies.
[`lcov`](https://github.com/linux-test-project/lcov) is required for generating HTML
output.  You can install it via
- Debian/Ubuntu: `sudo apt install lcov`
- Arch/Manjaro: `yay -S lcov`

Note that the code in this package assumes a reasonably recent `lcov` version when calling `genhtml`, ideally `1.13`, but `1.12` should work too. This does not prevent installation, only emits a warning.

## Usage

When generating test coverage, Julia places annotated `*.cov` source code files in the same directory as the source code itself. Those files are processed to evaluate coverage data, represented by the `PackageCoverage` struct, and are automatically removed by the package. An `coverage/lcov.info` file is also created in the package dir.  We recommend using this package
with packages added with the `Pkg.dev` installation option (which allows for easy
manipulation of the package directory).

To generate test coverage data do
```julia
using LocalCoverage
# pkg is the package name as a string, e.g. "LocalCoverage"
generate_coverage(pkg = nothing; run_test = true) # defaults shown
```
You can then navigate to the `coverage` subdirectory of the package directory (e.g.
`~/.julia/dev/PackageName/coverage`) and see the generated coverage summaries. Note that the test execution step may be skipped if `*.cov` files were already generated (possibly by some external package).  

To generate, and optionally open, the coverage report HTML do
```julia
html_coverage(coverage::PackageCoverage; open = false, dir = tempdir()) # defaults shown
```

A utility method is also provided to easily print coverage statistics and exit with a status reflecting if some given target coverage was met. It can be used from a shell by doing
```bash
julia --project -e'using LocalCoverage; report(target_coverage=90)'
```
