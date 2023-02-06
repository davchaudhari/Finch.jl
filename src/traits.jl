struct SparseData
    lvl
end

struct DenseData
    lvl
end

struct HollowData
    lvl
end

struct SolidData
    lvl
end

struct ElementData
    eltype
    default
end

struct RepeatData
    eltype
    default
end

struct Drop{Idx}
    idx::Idx
end

getindex_rep(tns, inds...) = getindex_rep_def(tns, map(ind -> ndims(ind) == 0 ? Drop(ind) : ind, inds)...)

getindex_rep_def(fbr::SolidData, idxs...) = getindex_rep_def(fbr.lvl, idxs...)
getindex_rep_def(fbr::HollowData, idxs...) = getindex_rep_def_hollow(getindex_rep_def(fbr.lvl, idxs...))
getindex_rep_def_hollow(subfbr::SolidData, idxs...) = HollowData(subfbr.lvl)
getindex_rep_def_hollow(subfbr::HollowData, idxs...) = subfbr

getindex_rep_def(lvl::SparseData, idx, idxs...) = getindex_rep_def_sparse(getindex_rep_def(lvl.lvl, idxs...), idx)
getindex_rep_def_sparse(subfbr::HollowData, idx::Drop) = HollowData(subfbr.lvl)
getindex_rep_def_sparse(subfbr::HollowData, idx) = HollowData(SparseData(subfbr.lvl))
getindex_rep_def_sparse(subfbr::HollowData, idx::Base.Slice) = HollowData(SparseData(subfbr.lvl))
getindex_rep_def_sparse(subfbr::SolidData, idx::Drop) = HollowData(subfbr.lvl)
getindex_rep_def_sparse(subfbr::SolidData, idx) = HollowData(SparseData(subfbr.lvl))
getindex_rep_def_sparse(subfbr::SolidData, idx::Base.Slice) = SolidData(SparseData(subfbr.lvl))

getindex_rep_def(lvl::DenseData, idx, idxs...) = getindex_rep_def_dense(getindex_rep_def(lvl.lvl, idxs...), idx)
getindex_rep_def_dense(subfbr::HollowData, idx::Drop) = HollowData(subfbr.lvl)
getindex_rep_def_dense(subfbr::HollowData, idx) = HollowData(DenseData(subfbr.lvl))
getindex_rep_def_dense(subfbr::SolidData, idx::Drop) = SolidData(subfbr.lvl)
getindex_rep_def_dense(subfbr::SolidData, idx) = SolidData(DenseData(subfbr.lvl))

getindex_rep_def(lvl::ElementData) = SolidData(lvl)

getindex_rep_def(lvl::RepeatData, idx::Drop) = SolidData(ElementLevel(lvl.eltype, lvl.default))
getindex_rep_def(lvl::RepeatData, idx) = SolidData(DenseLevel(ElementLevel(lvl.eltype, lvl.default)))
getindex_rep_def(lvl::RepeatData, idx::AbstractUnitRange) = SolidData(lvl)

fiber_ctr(fbr::SolidData) = :(Fiber($(fiber_ctr_solid(fbr.lvl))))
fiber_ctr_solid(lvl::DenseData) = :(Dense($(fiber_ctr_solid(lvl.lvl))))
fiber_ctr_solid(lvl::SparseData) = :(SparseList($(fiber_ctr_solid(lvl.lvl))))
fiber_ctr_solid(lvl::ElementData) = :(Element{$(lvl.default), $(lvl.eltype)}())
fiber_ctr_solid(lvl::RepeatData) = :(Repeat{$(lvl.default), $(lvl.eltype)}())
fiber_ctr(fbr::HollowData) = :(Fiber($(fiber_ctr_hollow(fbr.lvl))))
fiber_ctr_hollow(lvl::DenseData) = :(SparseList($(fiber_ctr_solid(lvl.lvl))))
fiber_ctr_hollow(lvl::SparseData) = :(SparseList($(fiber_ctr_solid(lvl.lvl))))
fiber_ctr_hollow(lvl::ElementData) = :(Element{$(lvl.default), $(lvl.eltype)}())
fiber_ctr_hollow(lvl::RepeatData) = :(Repeat{$(lvl.default), $(lvl.eltype)}())
