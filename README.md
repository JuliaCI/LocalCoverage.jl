# LocalCoverage.jl

![lifecycle](https://img.shields.io/badge/lifecycle-maturing-blue.svg)
[![build](https://github.com/tpapp/LocalCoverage.jl/workflows/CI/badge.svg)](https://github.com/tpapp/LocalCoverage.jl/actions?query=workflow%3ACI)
[![codecov.io](http://codecov.io/github/tpapp/LocalCoverage.jl/coverage.svg?branch=master)](http://codecov.io/github/tpapp/LocalCoverage.jl?branch=master)

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

Note that the code in this package assumes a reasonably recent `lcov` version when calling `genhtml`, ideally `1.13`, but `1.12` should work too. This only checked when building this package, and does not prevent installation, only emits a warning. See the discussion of [issue #1](https://github.com/tpapp/LocalCoverage.jl/issues/1) for a workaround.

`LocalCoverage` also provides an option to generate a
[Cobertura](https://cobertura.github.io/cobertura/) XML, which is used by JVM-related test
suites such as Jenkins.  Using this requires the Python module
[`lcov_cobertura`](https://github.com/eriwen/lcov-to-cobertura-xml).  With Python
installed, you can install this module via `pip install lcov_cobertura`.

## Usage
When generating test coverage, Julia places annotated `*.cov` source code files in the
same directory as the source code itself.  In addition, summary files will be placed in
the `coverage` subdirectory of the package directory.  We recommend using this package
with packages added with the `Pkg.dev` installation option (which allows for easy
manipulation of the package directory).

To generate test coverage files do
```julia
using LocalCoverage
# pkg is the package name as a string, e.g. "LocalCoverage"
generate_coverage(pkg, genhtml=true, show_summary=true, genxml=false) # defaults shown
```
You can then navigate to the `coverage` subdirectory of the package directory (e.g.
`~/.julia/dev/PackageName/coverage`) and see the generated coverage summaries.

To open the coverage report HTML in a browser do
```julia
open_coverage(pkg)
```

To delete all coverage files do
```julia
clean_coverage(pkg, rm_directory=true) # defaults shown
```
