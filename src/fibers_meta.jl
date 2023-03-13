using Base: Broadcast
using Base.Broadcast: Broadcasted, BroadcastStyle, AbstractArrayStyle
const AbstractArrayOrBroadcasted = Union{AbstractArray,Broadcasted}

"""
    fiber!(arr, default = zero(eltype(arr)))

Like [`fiber`](@ref), copies an array-like object `arr` into a corresponding,
similar `Fiber` datastructure. However, `fiber!` reuses memory whenever
possible, meaning `arr` may be rendered unusable.
"""
fiber!(arr, default=zero(eltype(arr))) = fiber(arr, default=default)

"""
    fiber(arr, default = zero(eltype(arr)))

Copies an array-like object `arr` into a corresponding, similar `Fiber`
datastructure. `default` is the default value to use for initialization and
sparse compression.

See also: [`fiber!`](@ref)

# Examples

```jldoctest
julia> println(summary(fiber(sparse([1 0; 0 1]))))
2×2 @fiber(d(sl(e(0))))

julia> println(summary(fiber(ones(3, 2, 4))))
3×2×4 @fiber(d(d(d(e(0.0)))))
```
"""
function fiber(arr, default=zero(eltype(arr)))
    Base.copyto!(Fiber((DenseLevel^(ndims(arr)))(Element{default}())), arr)
end

@generated function helper_equal(A, B)
    idxs = [Symbol(:i_, n) for n = 1:ndims(A)]
    return quote
        size(A) == size(B) || return false
        check = Scalar(true)
        @finch @loop($(reverse(idxs)...), check[] &= (A[$(idxs...)] == B[$(idxs...)]))
        return check[]
    end
end

function Base.:(==)(A::Fiber, B::Fiber)
    return helper_equal(A, B)
end

function Base.:(==)(A::Fiber, B::AbstractArray)
    return helper_equal(A, B)
end

function Base.:(==)(A::AbstractArray, B::Fiber)
    return helper_equal(A, B)
end

@generated function helper_isequal(A, B)
    idxs = [Symbol(:i_, n) for n = 1:ndims(A)]
    return quote
        size(A) == size(B) || return false
        check = Scalar(true)
        @finch @loop($(reverse(idxs)...), check[] &= isequal(A[$(idxs...)], B[$(idxs...)]))
        return check[]
    end
end

function Base.isequal(A:: Fiber, B::Fiber)
    return helper_isequal(A, B)
end

function Base.isequal(A:: Fiber, B::AbstractArray)
    return helper_isequal(A, B)
end

function Base.isequal(A:: AbstractArray, B::Fiber)
    return helper_isequal(A, B)
end

Base.getindex(arr::Fiber, inds...) = getindex_helper(arr, to_indices(arr, inds)...)
@generated function getindex_helper(arr::Fiber, inds...)
    @assert ndims(arr) == length(inds)
    N = ndims(arr)

    inds_ndims = ndims.(inds)
    if sum(inds_ndims) == 0
        return quote
            scl = Scalar($(default(arr)))
            @finch scl[] = arr[inds...]
            return scl[]
        end
    end

    T = eltype(arr)
    syms = [Symbol(:inds_, n) for n = 1:N]
    modes = [Symbol(:mode_, n) for n = 1:N]
    coords = map(1:N) do n
        if ndims(inds[n]) == 0
            syms[n]
        elseif inds[n] <: Base.Slice
            modes[n]
        else
            :($(syms[n])[$(modes[n])])
        end
    end
    dst_modes = modes[filter(n->ndims(inds[n]) != 0, 1:N)]
    
    dst = fiber_ctr(getindex_rep(data_rep(arr), inds...))

    quote
        win = $dst
        ($(syms...), ) = (inds...,)
        @finch begin
            win .= $(default(arr))
            @loop($(reverse(dst_modes)...), win[$(dst_modes...)] = arr[$(coords...)])
        end
        return win
    end
end

Base.setindex!(arr::Fiber, src, inds...) = setindex_helper(arr, src, to_indices(arr, inds)...)
@generated function setindex_helper(arr::Fiber, src, inds...)
    @assert ndims(arr) == length(inds)
    @assert ndims(src) == sum(ndims.(inds))
    N = ndims(arr)

    T = eltype(arr)
    syms = [Symbol(:inds_, n) for n = 1:N]
    modes = [Symbol(:mode_, n) for n = 1:N]
    coords = map(1:N) do n
        if ndims(inds[n]) == 0
            syms[n]
        elseif inds[n] <: Base.Slice
            modes[n]
        else
            :($(syms[n])[$(modes[n])])
        end
    end
    src_modes = modes[filter(n->ndims(inds[n]) != 0, 1:N)]
    
    quote
        ($(syms...), ) = (inds...,)
        @finch begin
            @loop($(reverse(src_modes)...), arr[$(coords...)] = src[$(src_modes...)])
        end
        return src
    end
end

#=
function Base.mapreduce(f, op, A::Fiber, As::AbstractArrayOrBroadcasted...; dims=:, init=nothing)=
    _mapreduce(f, op, A, As..., dims, init)
function _mapreduce(f, op, As..., dims, init)
    init === nothing && throw(ArgumentError("Finch requires an initial value for reductions."))
    init = something(init)
    allequal(ndims.(As)) || throw(ArgumentError("Finch cannot currently mapreduce arguments with differing numbers of dimensions"))
    allequal(axes.(As)) || throw(DimensionMismatchError("Finch cannot currently mapreduce arguments with differing size"))
    reduce(op, Broadcast.broadcasted(f, As...), dims, init)
end
=#

struct FinchStyle{N} <: BroadcastStyle
end
Base.Broadcast.BroadcastStyle(F::Type{<:Fiber}) = FinchStyle{ndims(F)}()
Base.Broadcast.broadcastable(fbr::Fiber) = fbr
Base.Broadcast.BroadcastStyle(a::FinchStyle{N}, b::FinchStyle{M}) where {M, N} = FinchStyle{max(M, N)}()
Base.Broadcast.BroadcastStyle(a::FinchStyle{N}, b::Broadcast.AbstractArrayStyle{M}) where {M, N} = FinchStyle{max(M, N)}()

pointwise_finch_instance(bc::Broadcast.Broadcasted, idxs) = FinchNotation.call_instance(FinchNotation.index_leaf_instance(bc.f), map((arg) -> pointwise_finch_instance(arg, idxs), bc.args)...)
pointwise_finch_instance(arg, idxs) = (FinchNotation.access_instance(arg, FinchNotation.reader_instance(), idxs[end - ndims(arg) + 1:end]...))

function Base.similar(bc::Broadcast.Broadcasted{FinchStyle{N}}, ::Type{T}, dims) where {N, T}
    idxs = [index_instance(Symbol(:i, n)) for n = 1:N]
    ex = pointwise_finch_instance(bc, idxs)
    similar_broadcast_helper(ex, idxs...)
end

function similar_broadcast_helper(ex, idxs...)
    N = length(idxs)
    contain(LowerJulia()) do ctx
        ex = virtualize(:ex, ex, ctx)
        idxs = [virtualize(:(idxs[$n]), idxs[n], ctx) for n = 1:N]
        pointwise_rep(data_rep(ex), idxs)
    end
end

function data_rep(ex::FinchNode)
    if ex.kind === access && ex.tns.kind === virtual
        return access(data_rep(ex.val), ex.mode, ex.idxs...)
    elseif istree(ex)
        similarterm(FinchNode, ex.kind, map(data_rep, arguments(ex)))
    else
        ex
    end
end

struct PointwiseSparseStyle end
struct PointwiseDenseStyle end
struct PointwiseRepeatStyle end
struct PointwiseElementStyle end

struct PointwiseRep
    idxs
end

stylize_access(node, ex::PointwiseRep, tns::SolidData) = stylize_access(node, ex, tns.lvl)
stylize_access(node, ex::PointwiseRep, tns::HollowData) = stylize_access(node, ex, tns.lvl)
stylize_access(node, ex::PointwiseRep, tns::SparseData) = PointwiseSparseStyle()
stylize_access(node, ex::PointwiseRep, tns::DenseData) = PointwiseDenseStyle()
stylize_access(node, ex::PointwiseRep, tns::RepeatData) = PointwiseRepeatStyle()

(ctx::PointwiseRep)(rep, idxs) = pointwise_rep(rep, idxs, Stylize(ctx)(expr_rep))
function (ctx::PointwiseRep)(rep, idxs, ::PointwiseSparseStyle)
    background = simplify(PostWalk(Chain([
        (@rule access(~ex::isvirtual, ~m, $(idxs[1]), i...) => access(pointwise_rep_sparse(ex.val), m, idxs[1], i...)),
    ]))(rep), LowerJulia())
    if isliteral(background)
        body = simplify(PostWalk(Chain([
            (@rule access(~ex::isvirtual, ~m, $(idxs[1]), i...) => access(pointwise_rep_body(ex.val), m, i...)),
        ]))(rep), LowerJulia())
        return SparseData(ctx(body))
    else
        ctx(rep, Stylize(background, ctx)(background))
    end
end

function (ctx::PointwiseRep)(expr_rep, idxs, ::PointwiseDenseStyle)
    body = simplify(PostWalk(Chain([
        (@rule access(~ex::isvirtual, ~m, $(idxs[1]), i...) => access(ex.lvl, m, i...)),
    ]))(rep), LowerJulia())
    return DenseData(ctx(body))
end

function (ctx::PointwiseRep)(expr_rep, idxs, ::PointwiseRepeatStyle)
    background = simplify(PostWalk(Chain([
        (@rule access(~ex::isvirtual, ~m, $(idxs[1]), i...) => default(ex.val)),
    ]))(rep), LowerJulia())
    @assert isliteral(background)
    return RepeatData(background.val, typeof(background.val))
end

function (ctx::PointwiseRep)(expr_rep, idxs, ::PointwiseElementStyle)
    background = simplify(PostWalk(Chain([
        (@rule access(~ex::isvirtual, ~m, $(idxs[1]), i...) => default(ex.val)),
    ]))(rep), LowerJulia())
    @assert isliteral(background)
    return ElementData(background.val, typeof(background.val))
end

pointwise_rep_sparse(ex::SparseData) = Fill(default(ex))
pointwise_rep_sparse(ex) = ex

#=
@generated function Base.similar(bc::Broadcasted{FinchStyle{N}}, ::Type{T}, dims) where {N, T}
    #TODO this ignores T and dims haha.
    return fiber_ctr(broadcast_rep(bc))
end

function finch_broadcast_expr(ex, ::Type{Broadcasted{Style, Axes, F, Args}}, ctx::LowerJulia, idxs) where {Style, Axes, F, Args}
    sym = ctx.freshen(:arg)
    push!(ctx.preamble, :($sym = $ex.f))
    args = map(enumerate(Args.parameters)) do (n, Arg)
        finch_broadcast_expr(:($ex.args[$n]), Arg, ctx, idxs)
    end
    return :($sym($(args...)))
end
function finch_broadcast_expr(ex, ::Type{T}, ctx::LowerJulia, idxs) where T
    sym = ctx.freshen(:arg)
    push!(ctx.preamble, :($sym = $ex))
    return :($sym[$(idxs[end - ndims(T) + 1:end]...)])
end


@generated function Base.copyto!(out, bc::Broadcasted{FinchStyle{N}}) where {N}
    ctx = LowerJulia()
    res = contain(ctx) do ctx_2
        idxs = [ctx_2.freshen(:idx, n) for n = 1:N]
        ex = finch_broadcast_expr(:bc, bc, ctx_2, idxs)
        quote
            @finch begin
                out .= $(default(out))
                @loop($(reverse(idxs)...), out[$(idxs...)] = $ex)
            end
        end
    end
    quote
        println($(QuoteNode(res)))
        $res
        out
    end

end

function reduce(op, bc::Broadcasted{FinchStyle{N}}, dims, init) where {N}
    T = Base.combine_eltypes(bc.f, bc.args::Tuple)
end
=#


@generated function copyto_helper!(dst, src)
    ndims(dst) > ndims(src) && throw(DimensionMismatch("more dimensions in destination than source"))
    ndims(dst) < ndims(src) && throw(DimensionMismatch("less dimensions in destination than source"))
    idxs = [Symbol(:i_, n) for n = 1:ndims(dst)]
    return quote
        @finch begin
            dst .= $(default(dst))
            @loop($(reverse(idxs)...), dst[$(idxs...)] = src[$(idxs...)])
        end
        return dst
    end
end

function Base.copyto!(dst::Fiber, src::Union{Fiber, AbstractArray})
    return copyto_helper!(dst, src)
end

function Base.copyto!(dst::Array, src::Fiber)
    return copyto_helper!(dst, src)
end

dropdefaults(src) = dropdefaults!(similar(src), src)

@generated function dropdefaults!(dst::Fiber, src)
    ndims(dst) > ndims(src) && throw(DimensionMismatch("more dimensions in destination than source"))
    ndims(dst) < ndims(src) && throw(DimensionMismatch("less dimensions in destination than source"))
    idxs = [Symbol(:i_, n) for n = 1:ndims(dst)]
    T = eltype(dst)
    d = default(dst)
    return quote
        tmp = Scalar{$d, $T}()
        @finch begin
            dst .= $(default(dst))
            @loop $(reverse(idxs)...) begin
                tmp .= $(default(dst))
                tmp[] = src[$(idxs...)]
                if !isequal(tmp[], $d)
                    dst[$(idxs...)] = tmp[]
                end
            end
        end
        return dst
    end
end

"""
    fsparse(I::Tuple, V,[ M::Tuple, combine])

Create a sparse COO fiber `S` such that `size(S) == M` and `S[(i[q] for i =
I)...] = V[q]`. The combine function is used to combine duplicates. If `M` is
not specified, it is set to `map(maximum, I)`. If the combine function is not
supplied, combine defaults to `+` unless the elements of V are Booleans in which
case combine defaults to `|`. All elements of I must satisfy 1 <= I[n][q] <=
M[n].  Numerical zeros are retained as structural nonzeros; to drop numerical
zeros, use dropzeros!.

See also: [`sparse`](https://docs.julialang.org/en/v1/stdlib/SparseArrays/#SparseArrays.sparse)

# Examples

julia> I = (
    [1, 2, 3],
    [1, 2, 3],
    [1, 2, 3]);

julia> V = [1.0; 2.0; 3.0];

julia> fsparse(I, V)
SparseCOO (0.0) [1:3×1:3×1:3]
│ │ │ 
└─└─└─[1, 1, 1] [2, 2, 2] [3, 3, 3]
      1.0       2.0       3.0    
"""
function fsparse(I::Tuple, V::Vector, shape = map(maximum, I), combine = eltype(V) isa Bool ? (|) : (+))
    C = map(tuple, I...)
    updater = false
    if !issorted(C)
        P = sortperm(C)
        C = C[P]
        V = V[P]
        updater = true
    end
    if !allunique(C)
        P = unique(p -> C[p], 1:length(C))
        C = C[P]
        push!(P, length(I[1]) + 1)
        V = map((start, stop) -> foldl(combine, @view V[start:stop - 1]), P[1:end - 1], P[2:end])
        updater = true
    end
    if updater
        I = map(i -> similar(i, length(C)), I)
        foreach(((p, c),) -> ntuple(n->I[n][p] = c[n], length(I)), enumerate(C))
    else
        I = map(copy, I)
    end
    return fsparse!(I, V, shape)
end

"""
    fsparse!(I::Tuple, V,[ M::Tuple])

Like [`fsparse`](@ref), but the coordinates must be sorted and unique, and memory
is reused.
"""
function fsparse!(I::Tuple, V, shape = map(maximum, I))
    return Fiber(SparseCOO{length(I), Tuple{map(eltype, I)...}, Int}(Element{zero(eltype(V))}(V), shape, I, [1, length(V) + 1]))
end

"""
    fsprand([rng],[type], m::Tuple,p::AbstractFloat,[rfn])

Create a random sparse tensor of size `m` in COO format, in which the
probability of any element being nonzero is independently given by `p` (and
hence the mean density of nonzeros is also exactly `p`). Nonzero values are
sampled from the distribution specified by `rfn` and have the type `type`. The
uniform distribution is used in case `rfn` is not specified. The optional `rng`
argument specifies a random number generator.

See also: (`sprand`)(https://docs.julialang.org/en/v1/stdlib/SparseArrays/#SparseArrays.sprand)

# Examples
```jldoctest; setup = :(using Random; Random.seed!(1234))
julia> fsprand(Bool, (3, 3), 0.5)
SparseCOO (false) [1:3,1:3]
├─├─[1, 1]: true
├─├─[3, 1]: true
├─├─[2, 2]: true
├─├─[3, 2]: true
├─├─[3, 3]: true  

julia> fsprand(Float64, (2, 2, 2), 0.5)
SparseCOO (0.0) [1:2,1:2,1:2]
├─├─├─[2, 2, 1]: 0.6478553157718558
├─├─├─[1, 1, 2]: 0.996665291437684
├─├─├─[2, 1, 2]: 0.7491940599574348 
```
"""
fsprand(n::Tuple, args...) = _fsprand_impl(n, sprand(mapfoldl(BigInt, *, n), args...))
fsprand(T::Type, n::Tuple, args...) = _fsprand_impl(n, sprand(T, mapfoldl(BigInt, *, n), args...))
fsprand(r::SparseArrays.AbstractRNG, n::Tuple, args...) = _fsprand_impl(n, sprand(r, mapfoldl(BigInt, *, n), args...))
fsprand(r::SparseArrays.AbstractRNG, T::Type, n::Tuple, args...) = _fsprand_impl(n, sprand(r, T, mapfoldl(BigInt, *, n), args...))
function _fsprand_impl(shape::Tuple, vec::SparseVector{Tv, Ti}) where {Tv, Ti}
    I = ((Vector{Ti}(undef, length(vec.nzind)) for _ in shape)...,)
    for (p, ind) in enumerate(vec.nzind)
        c = CartesianIndices(shape)[ind]
        ntuple(n->I[n][p] = c[n], length(shape))
    end
    return fsparse!(I, vec.nzval, shape)
end

"""
    fspzeros([type], shape::Tuple)

Create a random zero tensor of size `m`, with elements of type `type`. The
tensor is in COO format.

See also: (`spzeros`)(https://docs.julialang.org/en/v1/stdlib/SparseArrays/#SparseArrays.spzeros)

# Examples
```jldoctest
julia> fspzeros(Bool, (3, 3))
SparseCOO (false) [1:3,1:3]
    
julia> fspzeros(Float64, (2, 2, 2))
SparseCOO (0.0) [1:2,1:2,1:2]
```
"""
fspzeros(shape) = fspzeros(Float64, shape)
function fspzeros(::Type{T}, shape) where {T}
    return fsparse!(((Int[] for _ in shape)...,), T[], shape)
end

"""
    ffindnz(arr)

Return the nonzero elements of `arr`, as Finch understands `arr`. Returns `(I,
V)`, where `I` is a tuple of coordinate vectors, one for each mode of `arr`, and
`V` is a vector of corresponding nonzero values, which can be passed to
[`fsparse`](@ref).

See also: (`findnz`)(https://docs.julialang.org/en/v1/stdlib/SparseArrays/#SparseArrays.findnz)
"""
function ffindnz(src)
    tmp = Fiber(
        SparseCOOLevel{ndims(src)}(
        ElementLevel{zero(eltype(src)), eltype(src)}()))
    tmp = copyto!(tmp, src)
    nnz = tmp.lvl.pos[2] - 1
    tbl = tmp.lvl.tbl
    val = tmp.lvl.lvl.val
    (ntuple(n->tbl[n][1:nnz], ndims(src)), val[1:nnz])
end