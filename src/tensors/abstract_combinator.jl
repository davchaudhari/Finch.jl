abstract type AbstractCombinator <: AbstractTensor end
abstract type AbstractVirtualCombinator <: AbstractVirtualTensor end


#=
"""
    is_laminable(ctx, tns, protos)
    
Return a tuple of whether each dimension in a tensor is laminable, meaning that
it supports multiple loops through it.

The fallback for `is_laminable` will iteratively move the last element of
`protos` into the arguments of a function. This allows fibers to specialize on
the last arguments of protos rather than the first, as Finch is column major.

Scalars are always assumed to be readable and writable multiple times.
"""
function is_laminable(ctx, tns, subprotos, protos...)
    if isempty(subprotos)
        [false for _ in 1:ndims(tns)]
    else
        is_laminable(ctx, tns, subprotos[1:end-1], subprotos[end], protos...)
    end
end
=#