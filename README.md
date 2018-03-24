# LocalCoverage

[![Project Status: WIP – Initial development is in progress, but there has not yet been a stable, usable release suitable for the public.](http://www.repostatus.org/badges/latest/wip.svg)](http://www.repostatus.org/#wip)
[![Build Status](https://travis-ci.org/tpapp/LocalCoverage.jl.svg?branch=master)](https://travis-ci.org/tpapp/LocalCoverage.jl)
[![Coverage Status](https://coveralls.io/repos/tpapp/LocalCoverage.jl/badge.svg?branch=master&service=github)](https://coveralls.io/github/tpapp/LocalCoverage.jl?branch=master)
[![codecov.io](http://codecov.io/github/tpapp/LocalCoverage.jl/coverage.svg?branch=master)](http://codecov.io/github/tpapp/LocalCoverage.jl?branch=master)

This is a collection of trivial functions to facilitate generating and exploring test coverage information for Julia packages *locally*, without using any remote/cloud services.

## Installation

This package is not (yet) registered. You need to install it with

```julia
Pkg.clone("https://github.com/tpapp/LocalCoverage.jl.git")
```

Generating HTML needs the `genhtml` utility, which is part of [LCOV](http://ltp.sourceforge.net/coverage/lcov.php). On Debian/Ubuntu systems, use

```sh
sudo apt install lcov
```

Note that the code in this package assumes a reasonably recent `lcov` version when calling `genhtml`, ideally `1.13`, but `1.12` should work too. This is not checked. See the discussion of [issue #1](https://github.com/tpapp/LocalCoverage.jl/issues/1) for a workaround.

## Usage

```julia
using LocalCoverage
generate_coverage(pkg)  # generate coverage information
open_coverage(pkg)      # open in a browser
clean_coverage(pkg)     # cleanup
```

Works fine with [RoguePkg.jl](https://github.com/tpapp/RoguePkg.jl) for local packages.
