##############################################################################
##
## Parse FixedEffect
##
##
##############################################################################
struct FixedEffectTerm <: AbstractTerm
    x::Symbol
end
StatsModels.termvars(t::FixedEffectTerm) = [t.x]


fe(x::Term) = FixedEffectTerm(Symbol(x))

has_fe(::FixedEffectTerm) = true
has_fe(::FunctionTerm{typeof(fe)}) = true
has_fe(t::InteractionTerm) = any(has_fe(x) for x in t.terms)
has_fe(::AbstractTerm) = false
has_fe(t::FormulaTerm) = any(has_fe(x) for x in eachterm(t.rhs))


fesymbol(t::FixedEffectTerm) = t.x
fesymbol(t::FunctionTerm{typeof(fe)}) = Symbol(t.args_parsed[1])


function parse_fixedeffect(df::AbstractDataFrame, formula::FormulaTerm)
    fe = FixedEffect[]
    id = Symbol[]
    for term in eachterm(formula.rhs)
        result = parse_fixedeffect(df, term)
        if result != nothing
            push!(fe, result[1])
            push!(id, result[2])
        end
    end
    formula = FormulaTerm(formula.lhs, tuple((term for term in eachterm(formula.rhs) if !has_fe(term))...))
    return fe, id, formula
end

# Constructors from dataframe + Term
function parse_fixedeffect(df::AbstractDataFrame, t::AbstractTerm)
    if has_fe(t)
        st = fesymbol(t)
        return FixedEffect(df[!, st]), Symbol(:fe_, st)
    end
end

# Constructors from dataframe + InteractionTerm
function parse_fixedeffect(df::AbstractDataFrame, t::InteractionTerm)
    fes = (x for x in t.terms if has_fe(x))
    interactions = (x for x in t.terms if !has_fe(x))
    if !isempty(fes)
        # x1&x2 from (x1&x2)*id
        fe_names = [fesymbol(x) for x in fes]
        fe = FixedEffect(group((df[!, fe_name] for fe_name in fe_names)...); interaction = _multiply(df, Symbol.(interactions)))
        interactions = setdiff(Symbol.(terms(t)), fe_names)
        s = vcat(["fe_" * string(fe_name) for fe_name in fe_names], string.(interactions))
        return fe, Symbol(reduce((x1, x2) -> x1*"&"*x2, s))
    end
end


function _multiply(df, ss::Vector)
    if isempty(ss)
        out = Ones(size(df, 1))
    else
        out = ones(size(df, 1))
        for j in eachindex(ss)
            _multiply!(out, df[!, ss[j]])
        end
    end
    return out
end
function _multiply!(out, v)
    for i in eachindex(out)
        if v[i] === missing
            # may be missing when I remove singletons
            out[i] = 0.0
        else
            out[i] = out[i] * v[i]
        end
    end
end



  
##############################################################################
##
## Old one
##
##
##############################################################################

function oldparse_fixedeffect(df::AbstractDataFrame, feformula::FormulaTerm)
    fe = FixedEffect[]
    id = Symbol[]
    for term in eachterm(feformula.rhs)
        result = oldparse_fixedeffect(df, term, feformula)
        if result != nothing
            push!(fe, result[1])
            push!(id, result[2])
        end
    end
    return fe, id
end

# Constructors from dataframe + Term
function oldparse_fixedeffect(df::AbstractDataFrame, a::Term, feformula::FormulaTerm)
    v = df[!, Symbol(a)]
    if isa(v, CategoricalVector)
        return FixedEffect(v), Symbol(a)
    else
        # x from x*id -> x + id + x&id
        if !any(isa(term, InteractionTerm) & (a ∈ terms(term)) for term in eachterm(feformula.rhs))
               error("The term $(a) in fe= is a continuous variable. Convert it to a categorical variable using 'categorical'.")
        end
    end
end

# Constructors from dataframe + InteractionTerm
function oldparse_fixedeffect(df::AbstractDataFrame, a::InteractionTerm, feformula::FormulaTerm)
    factorvars, interactionvars = _split(df, a)
    if !isempty(factorvars)
        # x1&x2 from (x1&x2)*id
        fe = FixedEffect((df[!, v] for v in factorvars)...; interaction = old_multiply(df, interactionvars))
        id = old_name(Symbol.(terms(a)))
        return fe, id
    end
end

function _split(df::AbstractDataFrame, a::InteractionTerm)
    factorvars, interactionvars = Symbol[], Symbol[]
    for s in terms(a)
        s = Symbol(s)
        isa(df[!, s], CategoricalVector) ? push!(factorvars, s) : push!(interactionvars, s)
    end
    return factorvars, interactionvars
end

function old_multiply(df, ss::Vector{Symbol})
    if isempty(ss)
        out = Ones(size(df, 1))
    else
        out = ones(size(df, 1))
        for j in eachindex(ss)
            old_multiply!(out, df[!, ss[j]])
        end
    end
    return out
end

function old_multiply!(out, v)
    for i in eachindex(out)
        if v[i] === missing
            # may be missing when I remove singletons
            out[i] = 0.0
        else
            out[i] = out[i] * v[i]
        end
    end
end

function old_name(s::Vector{Symbol})
    if isempty(s)
        out = nothing
    else
        out = Symbol(reduce((x1, x2) -> string(x1)*"x"*string(x2), s))
    end
    return out
end