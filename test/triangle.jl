using MatrixDepot
using Finch
using BenchmarkTools
using SparseArrays
using LinearAlgebra
using Cthulhu
using Profile

function tri(mtx)
    println("tri: $mtx")
    A_ref = SparseMatrixCSC(mdopen(mtx).A)
    (m, n) = size(A_ref)
    A = Finch.Fiber(
        Solid(m,
        HollowList(n, A_ref.colptr, A_ref.rowval,
        Element{0.0, Float64}(A_ref.nzval))))
    A2 = A
    A3 = A
    C = Finch.Fiber(
        Element{0.0, Float64}(zeros(1)))
    #=
    A = Finch.Fiber(
        Solid(m,
        Solid(n,
        Element{0.0, Float64}(A_ref.nzval))))
    ex = Finch.@index_program_instance @loop i j k C[] += A[i, k] * A[i, j] * A[j, k]
    display(Finch.execute_code_lowered(:ex, typeof(ex)))
    println()
    exit()
    ex = Finch.@index_program_instance @loop i j k C[] += A[i, k] * A[i, j] * A[j, k]
    display(Finch.execute_code_lowered(:ex, typeof(ex)))
    println()
    exit()
    ex = Finch.@index_program_instance @loop i j k C[] += A[i, k::gallop] * A[i, j] * A[j, k::gallop]
    display(Finch.execute_code_lowered(:ex, typeof(ex)))
    println()
    =#
    @index @loop i j k C[] += A[i, k::gallop] * A2[i, j] * A3[j, k::gallop]
    println(FiberArray(C)[])
    @index @loop i j k C[] += A[i, k] * A2[i, j] * A3[j, k]
    println(FiberArray(C)[])
    println(sum(A_ref .* (A_ref * A_ref)))
    #println(@descend execute(ex))

    println("Finch:")
    @btime (A = $A; A2=$A; A3=$A; C = $C; @index @loop i j k C[] += A[i, k::gallop] * A2[i, j] * A3[j, k::gallop])

    println("Finch:")
    @btime (A = $A; A2=$A; A3=$A; C = $C; @index @loop i j k C[] += A[i, k] * A2[i, j] * A3[j, k])

    println("Julia:")
    @btime sum($A_ref .* ($A_ref * $(transpose(A_ref))))
end

tri("SNAP/web-BerkStan")
tri("SNAP/web-NotreDame")
tri("SNAP/roadNet-PA")
exit()
tri("VDOL/spaceStation_5")
tri("DIMACS10/sd2010")
tri("Boeing/ct20stif")
tri("Bai/bfwb398")
tri("SNAP/soc-Epinions1")
tri("SNAP/email-EuAll")
tri("SNAP/wiki-Talk")