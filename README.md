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

`LocalCoverage` also provides an option to generate a
[Cobertura](https://cobertura.github.io/cobertura/) XML, which is used by JVM-related test
suites such as Jenkins.  This can be done either with:

- The native Julia implementation via the `write_lcov_to_xml` function,
- The original implementation using the `generate_xml` function.

The second option (`generate_xml`) requires the Python module
[`lcov_cobertura`](https://github.com/eriwen/lcov-to-cobertura-xml) (>= v2.0.1).
With Python installed, you can install this module via `pip install lcov_cobertura`.

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

You'll see output during testing like:

```text
┌─────────────────────┬───────┬─────┬──────┬──────┬──────────┐
│ Filename            │ Lines │ Hit │ Miss │    % │ Gaps     │
├─────────────────────┼───────┼─────┼──────┼──────┼──────────┤
│ src/DummyPackage.jl │     1 │   0 │    1 │   0% │ 6        │
│ src/bar.jl          │     2 │   1 │    1 │  50% │ 3        │
│ src/corge/corge.jl  │     1 │   1 │    0 │ 100% │          │
│ src/corge/grault.jl │     1 │   0 │    1 │   0% │ 2        │
│ src/qux.jl          │     2 │   0 │    2 │   0% │ 2, 5     │
├─────────────────────┼───────┼─────┼──────┼──────┼──────────┤
│ TOTAL               │     7 │   2 │    5 │  29% │          │
└─────────────────────┴───────┴─────┴──────┴──────┴──────────┘
```

You can then navigate to the `coverage` subdirectory of the package directory (e.g.
`~/.julia/dev/PackageName/coverage`) and see the generated coverage summaries. Note that the test execution step may be skipped if `*.cov` files were already generated (possibly by some external package).

To generate, and optionally open, the coverage report HTML do

```julia
html_coverage(coverage::PackageCoverage; open = false, dir = tempdir()) # defaults shown
```

To generate a Jest-compatible `coverage-summary.json` report, pass the `json_summary = true` option to `generate_coverage()` (optionally specifying the filename via `json_summary_filename`):

```julia
generate_coverage(pkg = nothing; json_summary = true, json_summary_filename = "coverage-summary.json") # defaults shown
```

If `test_args` are provided, the top level `"total"` key is replaced with the name of the test set.

To generate a Jest-compatible `coverage-summary.json` report from existing `PackageCoverage` data do

```julia
generate_json_summary(coverage::PackageCoverage, filename = "coverage-summary.json"; test_args = [""]) # defaults shown
```

### Coverage Delta and Comparison (CI)

You can compare two coverage JSON summaries (either from file paths or directly from JSON strings) to print a delta table and check if coverage has decreased:

```julia
# Compare two summaries. Returns true if coverage did not decrease, false if it did.
compare_coverage_json_summaries("old-summary.json", "new-summary.json")
```

You can also integrate this check directly into `generate_coverage()`, which is very useful for continuous integration (CI) environments to fail a build if coverage drops:

```julia
# Runs tests, generates the current summary, prints a comparison table against
# "previous-summary.json", and throws an error if overall coverage decreased.
generate_coverage(pkg; 
                  json_comparison_summary_filename = "previous-summary.json",
                  json_summary_comparison_fail_on_decrease = true)
```

The comparison output looks like:

```text
┌─────────────────────┬──────────────┬──────────────┬────────┐
│ File/Section        │ Old Coverage │ New Coverage │  Delta │
├─────────────────────┼──────────────┼──────────────┼────────┤
│ total               │        20.0% │       28.57% │ +8.57% │
│ src/DummyPackage.jl │            - │         0.0% │      - │
│ src/bar.jl          │        20.0% │        50.0% │ +30.0% │
│ src/corge/corge.jl  │            - │       100.0% │      - │
│ src/corge/grault.jl │            - │         0.0% │      - │
│ src/qux.jl          │            - │         0.0% │      - │
└─────────────────────┴──────────────┴──────────────┴────────┘
```

A utility method is also provided to easily print coverage statistics and exit with a status reflecting if some given target coverage was met. It can be used from a shell by doing

```bash
julia --project -e'using LocalCoverage; report_coverage_and_exit(target_coverage=90)'
```
