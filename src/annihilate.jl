
@slots a b c d e i j f g rules = [
    (@rule @_f($f(a...)) => if isliteral(f) && all(isliteral, a) && length(a) >= 1 literal(getvalue(f)(getvalue.(a)...)) end),

    #((a) -> if isliteral(a) && isliteral(getvalue(a)) getvalue(a) end), #only quote when necessary

    (@rule @_f($a[i...] = $b) => if b == literal(default(a)) pass(a) end), #TODO either default needs to get defined on all chunks, or we need to guard this

    (@rule @_f(@loop $i @pass(a...)) => pass(a...)),
    (@rule @_f(@chunk $i $a @pass(b...)) => pass(b...)),
    (@rule @_f(@pass(a...) where $b) => pass(a...)),
    (@rule @_f($a where @pass()) => a),
    (@rule @_f(@multi(a..., @pass(b...), @pass(c...), d...)) => @f(@multi(a..., @pass(b..., c...), d...))),
    (@rule @_f(@multi(@pass(a...))) => @f(@pass(a...))),
    (@rule @_f(@multi()) => @f(@pass())),
    (@rule @_f((@pass(a...);)) => pass(a...)),

    (@rule @_f($a where $b) => begin
        @slots c d i j f g begin
            props = Dict()
            b_2 = Postwalk(Chain([
                (@rule @_f($c[i...] = $d) => if isliteral(d)
                    props[getname(c)] = d
                    pass()
                end),
                (@rule @_f(@pass(c...)) => begin
                    for d in c
                        props[getname(d)] = literal(default(d)) #TODO is this okay?
                    end
                    pass()
                end),
            ]))(b)
            if b_2 != nothing
                a_2 = Rewrite(Postwalk(@rule @_f($c[i...]) => get(props, getname(c), nothing)))(a)
                @f $a_2 where $b_2
            end
        end
    end),
    #(@rule @_f(a where @pass(b...)) => a),#can't do this bc produced tensors won't get initialized ?

    (@rule @_f(max(a...) >= $b) => @f or($(map(x -> @f($x >= $b), a)...))),
    (@rule @_f(max(a...) > $b) => @f or($(map(x -> @f($x > $b), a)...))),
    (@rule @_f(max(a...) <= $b) => @f and($(map(x -> @f($x <= $b), a)...))),
    (@rule @_f(max(a...) < $b) => @f and($(map(x -> @f($x < $b), a)...))),
    (@rule @_f(min(a...) <= $b) => @f or($(map(x -> @f($x <= $b), a)...))),
    (@rule @_f(min(a...) < $b) => @f or($(map(x -> @f($x < $b), a)...))),
    (@rule @_f(min(a...) >= $b) => @f and($(map(x -> @f($x >= $b), a)...))),
    (@rule @_f(min(a...) > $b) => @f and($(map(x -> @f($x > $b), a)...))),
    (@rule @_f(min(a..., min(b...), c...)) => @f min(a..., b..., c...)),
    (@rule @_f(max(a..., max(b...), c...)) => @f max(a..., b..., c...)),
    (@rule @_f(min(a...)) => if !(issorted(a, by = Lexicography)) @f min($(sort(a, by = Lexicography)...)) end),
    (@rule @_f(max(a...)) => if !(issorted(a, by = Lexicography)) @f max($(sort(a, by = Lexicography)...)) end),
    (@rule @_f(min(a...)) => if !(allunique(a)) @f min($(unique(a)...)) end),
    (@rule @_f(max(a...)) => if !(allunique(a)) @f max($(unique(a)...)) end),
    (@rule @_f(+(a..., +(b...), c...)) => @f +(a..., b..., c...)),
    (@rule @_f(+(a...)) => if count(isliteral, a) >= 2 @f +($(filter(!isliteral, a)...), $(literal(+(getvalue.(filter(isliteral, a))...)))) end),
    (@rule @_f(+(a..., 0, b...)) => @f +(a..., b...)),
    (@rule @_f(or(a..., false, b...)) => @f or(a..., b...)),
    (@rule @_f(or(a..., true, b...)) => @f true),
    (@rule @_f(or($a)) => a),
    (@rule @_f(or()) => @f false),
    (@rule @_f(and(a..., true, b...)) => @f and(a..., b...)),
    (@rule @_f(and(a..., false, b...)) => @f false),
    (@rule @_f(and($a)) => a),
    (@rule @_f((0 / $a)) => 0),

    (@rule @_f(ifelse(true, $a, $b)) => a),
    (@rule @_f(ifelse(false, $a, $b)) => b),
    (@rule @_f(ifelse($a, $b, $b)) => b),

    (@rule @_f(and()) => @f true),
    (@rule @_f((+)($a)) => a),
    (@rule @_f(- +($a, b...)) => @f +(- $a, - +(b...))),
    (@rule @_f($a[i...] += 0) => pass(a)),
    (@rule @_f(-0.0) => @f 0.0),

    (@rule @_f($a[i...] <<$f>>= $($(literal(missing)))) => pass(a)),
    (@rule @_f($a[i..., $($(literal(missing))), j...] <<$f>>= $b) => pass(a)),
    (@rule @_f($a[i..., $($(literal(missing))), j...]) => literal(missing)),
    (@rule @_f(coalesce(a..., $($(literal(missing))), b...)) => @f coalesce(a..., b...)),
    (@rule @_f(coalesce(a..., $b, c...)) => if isvalue(b) && !(Missing <: b.type); @f(coalesce(a..., $b)) end),
    (@rule @_f(coalesce(a..., $b, c...)) => if isliteral(b) && b != literal(missing); @f(coalesce(a..., $b)) end),
    (@rule @_f(coalesce($a)) => a),

    (@rule @_f($a - $b) => @f $a + - $b),
    (@rule @_f(- (- $a)) => a),

    (@rule @_f(*(a..., *(b...), c...)) => @f *(a..., b..., c...)),
    (@rule @_f(*(a...)) => if count(isliteral, a) >= 2 @f(*($(filter(!isliteral, a)...), $(literal(*(getvalue.(filter(isliteral, a))...))))) end),
    (@rule @_f(*(a..., 1, b...)) => @f *(a..., b...)),
    (@rule @_f(*(a..., 0, b...)) => @f 0),
    (@rule @_f((*)($a)) => a),
    (@rule @_f((*)(a..., - $b, c...)) => @f -(*(a..., $b, c...))),
    (@rule @_f($a[i...] *= 1) => pass(a)),
    (@rule @_f(@sieve true $a) => a),
    (@rule @_f(@sieve false $a) => pass(getresults(a)...)),

    (@rule @_f(@chunk $i $a ($b[j...] <<min>>= $d)) => if Finch.isliteral(d) && i ∉ j
        @f (b[j...] <<min>>= $d)
    end),
    (@rule @_f(@chunk $i $a @multi b... ($c[j...] <<min>>= $d) e...) => begin
        if Finch.isliteral(d) && i ∉ j
            @f @multi (c[j...] <<min>>= $d) @chunk $i a @f(@multi b... e...)
        end
    end),
    (@rule @_f(@chunk $i $a ($b[j...] <<max>>= $d)) => if Finch.isliteral(d) && i ∉ j
        @f (b[j...] <<max>>= $d)
    end),
    (@rule @_f(@chunk $i $a @multi b... ($c[j...] <<max>>= $d) e...) => begin
        if Finch.isliteral(d) && i ∉ j
            @f @multi (c[j...] <<max>>= $d) @chunk $i a @f(@multi b... e...)
        end
    end),
    (@rule @_f(@chunk $i $a ($b[j...] += $d)) => begin
        if getname(i) ∉ getunbound(d) && i ∉ j
            @f (b[j...] += $(extent(a)) * $d)
        end
    end),
    (@rule @_f(@chunk $i $a @multi b... ($c[j...] += $d) e...) => begin
        if getname(i) ∉ getunbound(d) && i ∉ j
            @f @multi (c[j...] += $(extent(a)) * $d) @chunk $i a @f(@multi b... e...)
        end
    end),
]

@kwdef mutable struct Simplify
    body
end

struct SimplifyStyle end

(ctx::Stylize{LowerJulia})(::Simplify) = SimplifyStyle()
combine_style(a::DefaultStyle, b::SimplifyStyle) = SimplifyStyle()
combine_style(a::ThunkStyle, b::SimplifyStyle) = ThunkStyle()
combine_style(a::SimplifyStyle, b::SimplifyStyle) = SimplifyStyle()

@kwdef struct SimplifyVisitor
    ctx
end

function (ctx::SimplifyVisitor)(node)
    if istree(node)
        similarterm(node, operation(node), map(ctx, arguments(node)))
    else
        node
    end
end

function (ctx::SimplifyVisitor)(node::CINNode)
    if node.kind === virtual
        convert(CINNode, ctx(node.val))
    elseif istree(node)
        similarterm(node, operation(node), map(ctx, arguments(node)))
    else
        node
    end
end

(ctx::SimplifyVisitor)(node::Simplify) = node.body

function simplify(node)
    global rules
    Rewrite(Fixpoint(Prewalk(Chain(rules))))(node)
end

function (ctx::LowerJulia)(root, ::SimplifyStyle)
    global rules
    root = SimplifyVisitor(ctx)(root)
    root = simplify(root)
    ctx(root)
end

add_rules!(new_rules) = union!(rules, new_rules)

IndexNotation.isliteral(::Simplify) =  false

struct Lexicography
    arg
end

function Base.isless(a::Lexicography, b::Lexicography)
    (a, b) = a.arg, b.arg
    #@assert which(priority, Tuple{typeof(a)}) == which(priority, Tuple{typeof(b)}) || priority(a) != priority(b)
    if a != b
        a_key = (priority(a), comparators(a)...)
        b_key = (priority(b), comparators(b)...)
        @assert a_key < b_key || b_key < a_key "a = $a b = $b a_key = $a_key b_key = $b_key"
        return a_key < b_key
    end
    return false
end

function Base.:(==)(a::Lexicography, b::Lexicography)
    (a, b) = a.arg, b.arg
    #@assert which(priority, Tuple{typeof(a)}) == which(priority, Tuple{typeof(b)}) || priority(a) != priority(b)
    a_key = (priority(a), comparators(a)...)
    b_key = (priority(b), comparators(b)...)
    return a_key == b_key
end

priority(::Type) = (0, 5)
comparators(x::Type) = (string(x),)

priority(::Missing) = (0, 4)
comparators(::Missing) = (1,)

priority(::Number) = (1, 1)
comparators(x::Number) = (x, sizeof(x), typeof(x))

priority(::Function) = (1, 2)
comparators(x::Function) = (string(x),)

priority(::Symbol) = (2, 0)
comparators(x::Symbol) = (x,)

priority(::Expr) = (2, 1)
comparators(x::Expr) = (x.head, map(Lexicography, x.args)...)

#priority(::Workspace) = (3,3)
#comparators(x::Workspace) = (x.n,)

#TODO this works for now, but reconsider this later
priority(node::CINNode) = (3, 4)
function comparators(node::CINNode)
    if node.kind === value
        return (node.kind, Lexicography(node.val), Lexicography(node.type))
    elseif node.kind === literal
        return (node.kind, Lexicography(node.val))
    elseif node.kind === virtual
        return (node.kind, Lexicography(node.val))
    elseif node.kind === name
        return (node.kind, Lexicography(node.val))
    elseif istree(node)
        return (node.kind, map(Lexicography, node.children))
    else
        error("unimplemented")
    end
end
#TODO these are nice defaults if we want to allow nondeterminism
#priority(::Any) = (Inf,)
#comparators(x::Any) = hash(x)