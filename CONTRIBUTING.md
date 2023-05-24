We welcome contributions to Finch, and follow the [Julia contributing
guidelines](https://github.com/JuliaLang/julia/blob/master/CONTRIBUTING.md).  If
you use or want to use Finch and have a question or bug, please do file a
[Github issue](https://github.com/willow-ahrens/Finch.jl/issues)!  If you want
to contribute to Finch, please first file an issue to double check that there is
interest from a contributor in the feature.

## Testing

All pull requests should pass continuous integration testing before merging.
The test suite has a few options, which are accessible through running the test
suite directly as `julia tests/runtests.jl`.

Finch compares compiler output against reference versions. If you run the test
suite (`test/runtests.jl`) directly you can pass the `--overwrite` flag to tell
the test suite to overwrite the reference.  Because the reference output depends
on the system word size, you'll need to generate reference output for 32-bit and
64-bit builds of Julia to get Finch to pass tests. The easiest way to do this is
to run each 32-bit or 64-bit build of Julia on a system that supports it. You
can [Download](https://julialang.org/downloads/) multiple builds yourself or use
[juliaup](https://github.com/JuliaLang/juliaup) to manage multiple versions.
Using juliaup, it might look like this:

```
julia +release~x86 tests/runtests.jl --overwrite
julia +release~x64 tests/runtests.jl --overwrite
```

The test suite takes a while to run. You can filter to only run a selection of
test suites by specifying them as positional arguments, e.g.

```
julia tests/runtests.jl constructors conversions representation
```

This information is summarized with `julia tests/runtests.jl --help`