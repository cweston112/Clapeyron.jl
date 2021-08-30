abstract type MHV2RuleModel <: MixingRule end

struct MHV2Rule{γ} <: MHV2RuleModel
    components::Array{String,1}
    activity::γ
end

has_sites(::Type{<:MHV2RuleModel}) = false
has_groups(::Type{<:MHV2RuleModel}) = false
built_by_macro(::Type{<:MHV2RuleModel}) = false

function Base.show(io::IO, mime::MIME"text/plain", model::MHV2Rule)
    return eosshow(io, mime, model)
end

function Base.show(io::IO, model::MHV2Rule)
    return eosshow(io, model)
end

export MHV2Rule
function MHV2Rule(components::Vector{String}; activity = Wilson, userlocations::Vector{String}=String[],activity_userlocations::Vector{String}=String[], verbose::Bool=false)
    init_activity = activity(components;userlocations = activity_userlocations,verbose)
    
    model = MHV2Rule(components, init_activity)
    return model
end

function mixing_rule(model::RKModel,V,T,z,mixing_model::MHV2RuleModel,α,a,b)
    n = sum(z)
    x = z./n
    invn2 = (one(n)/n)^2
    g_E = excess_gibbs_free_energy(mixing_model.activity,1e5,T,z) / n
    b̄ = dot(z,Symmetric(b),z) * invn2

    ᾱ = a.*sqrt.(α.*α')./(b*R̄*T)

    q1 = -0.4783
    q2 = -0.0047
    c  = -q1*sum(x[i]*ᾱ[i,i] for i ∈ @comps)-q2*sum(x[i]*ᾱ[i,i]^2 for i ∈ @comps)-g_E/(R̄*T)-sum(x[i]*log(b̄/b[i,i]) for i ∈ @comps)

    ā = b̄*R̄*T*(-q1-sqrt(q1^2-4*q2*c))/(2*q2)
    return ā,b̄
end

function mixing_rule(model::PRModel,V,T,z,mixing_model::MHV2RuleModel,α,a,b)
    n = sum(z)
    x = z./n
    invn2 = (one(n)/n)^2
    g_E = excess_gibbs_free_energy(mixing_model.activity,1e5,T,z) / n
    b̄ = dot(z,Symmetric(b),z) * invn2

    ᾱ = a.*sqrt.(α.*α')./(b*R̄*T)

    q1 = -0.4347
    q2 = -0.003654
    c  = -q1*sum(x[i]*ᾱ[i,i] for i ∈ @comps)-q2*sum(x[i]*ᾱ[i,i]^2 for i ∈ @comps)-g_E/(R̄*T)-sum(x[i]*log(b̄/b[i,i]) for i ∈ @comps)

    ā = b̄*R̄*T*(-q1-sqrt(q1^2-4*q2*c))/(2*q2)
    return ā,b̄
end

is_splittable(::MHV2Rule) = true