#!/usr/bin/env julia
if abspath(PROGRAM_FILE) == @__FILE__
    using Pkg
    Pkg.activate(@__DIR__)
    Pkg.develop(PackageSpec(path = joinpath(@__DIR__, "..")))
    Pkg.resolve()
    Pkg.instantiate()
end

# This file was copied from Transducers.jl
# which is available under an MIT license (see LICENSE).
using PkgBenchmark

function mkconfig(; kwargs...)
    return BenchmarkConfig(env = Dict("JULIA_NUM_THREADS" => "1"); kwargs...)
end

group_target = benchmarkpkg(
    dirname(@__DIR__),
    mkconfig(),
    resultfile = joinpath(@__DIR__, "result-target.json"),
)

group_baseline = benchmarkpkg(
    dirname(@__DIR__),
    mkconfig(id = "main"),
    resultfile = joinpath(@__DIR__, "result-baseline.json"),
)

judgement = judge(group_target, group_baseline)

include("pprintjudge.jl")