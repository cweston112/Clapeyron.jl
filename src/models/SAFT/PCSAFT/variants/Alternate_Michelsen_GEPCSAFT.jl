
abstract type AltAdvGEPCSAFTModel <: PCSAFTModel end


struct AltAdvGEPCSAFT{I <: IdealModel,T,γ} <: AltAdvGEPCSAFTModel
    components::Array{String,1}
    sites::SiteParam
    activity::γ
    params::PCSAFTParam{T}
    idealmodel::I
    assoc_options::AssocOptions
    Λ::T
    references::Array{String,1}
end

"""
    AltAdvGEPCSAFT <: SAFTModel

    AltAdvGEPCSAFT(components;
    idealmodel = BasicIdeal,
    userlocations = String[],
    ideal_userlocations = String[],
    reference_state = nothing,
    verbose = false,
    assoc_options = AssocOptions())

## Input parameters
- `Mw`: Single Parameter (`Float64`) - Molecular Weight `[g/mol]`
- `segment`: Single Parameter (`Float64`) - Number of segments (no units)
- `sigma`: Single Parameter (`Float64`) - Segment Diameter [`A°`]
- `epsilon`: Single Parameter (`Float64`) - Reduced dispersion energy  `[K]`
- `k`: Pair Parameter (`Float64`) (optional) - Binary Interaction Paramater (no units)
- `epsilon_assoc`: Association Parameter (`Float64`) - Reduced association energy `[K]`
- `bondvol`: Association Parameter (`Float64`) - Association Volume `[m^3]`

## Model Parameters
- `Mw`: Single Parameter (`Float64`) - Molecular Weight `[g/mol]`
- `segment`: Single Parameter (`Float64`) - Number of segments (no units)
- `sigma`: Pair Parameter (`Float64`) - Mixed segment Diameter `[m]`
- `epsilon`: Pair Parameter (`Float64`) - Mixed reduced dispersion energy`[K]`
- `epsilon_assoc`: Association Parameter (`Float64`) - Reduced association energy `[K]`
- `bondvol`: Association Parameter (`Float64`) - Association Volume

## Input models
- `idealmodel`: Ideal Model
- `activity`: Activity model

## Description

Perturbed-Chain SAFT (PC-SAFT), with Gᴱ mixing rule - using the Michelsen (0 pressure) limit.

"""
AltAdvGEPCSAFT

export AltAdvGEPCSAFT
function AltAdvGEPCSAFT(components;
    idealmodel = BasicIdeal,
    activity = UNIFAC,
    userlocations = String[],
    ideal_userlocations = String[],
    activity_userlocations = String[],
    assoc_options = AssocOptions(),
    reference_state = nothing,
    Λ = 1.0,
    verbose = false)

    params = getparams(components, ["SAFT/PCSAFT/PCSAFT_like.csv","SAFT/PCSAFT/PCSAFT_unlike.csv","SAFT/PCSAFT/PCSAFT_assoc.csv"]; userlocations = userlocations, verbose = verbose)
    sites = params["sites"]
    segment = params["segment"]
    k = get(params,"k",nothing)
    Mw = params["Mw"]
    params["sigma"].values .*= 1E-10
    sigma = sigma_LorentzBerthelot(params["sigma"])
    epsilon = epsilon_LorentzBerthelot(params["epsilon"], k)
    epsilon_assoc = params["epsilon_assoc"]
    bondvol = params["bondvol"]

    packagedparams = PCSAFTParam(Mw, segment, sigma, epsilon, epsilon_assoc, bondvol)

    init_idealmodel = init_model(idealmodel,components,ideal_userlocations,verbose)
    init_activity = init_model(activity,components,activity_userlocations,verbose)
    references = String["10.1021/acs.iecr.2c03464"]
    model = AltAdvGEPCSAFT(format_components(components), sites, init_activity, packagedparams, init_idealmodel, assoc_options, Λ, references)
    set_reference_state!(model,reference_state;verbose)
    return model
end

function _pcsaft(model::AltAdvGEPCSAFT{I,T}) where {I,T}
    return PCSAFT{I,T}(model.components,model.sites,model.params,model.idealmodel,model.assoc_options,model.references)
end

function m2ϵσ3(model::AltAdvGEPCSAFTModel, V, T, z, _data=@f(data))

    function q_i(α, b, m)
        c = [1.2568408567951958, 18.8500357205474445, 0.2568408567951958, 4.3428354083976375, 3.21234466508957, 205.67648963539912]
        α^2 - (c[1]*m + c[2])*α + c[3]*m^2 + c[4]*m + c[5]*log(b) + c[6]
    end

    function α_mix(q̄,b̄,m̄)
        c = [1.2568408567951958, 18.8500357205474445, 0.2568408567951958, 4.3428354083976375, 3.21234466508957, 205.67648963539912]
        A = 1
        B = - (c[1]*m̄ + c[2])
        C = c[3]*m̄^2 + c[4]*m̄ + c[5]*log(b̄) + c[6]- q̄
        # Solve the quadratic equation A*α^2 + B*α + C = 0
        return (-B-sqrt(B^2 - 4*A*C))/(2*A)
    end

    di,ζ0,ζ1,ζ2,ζ3,m̄ = _data
    Tnum = promote_type(eltype(z), typeof(V), typeof(T))
    act_model = typeof(model.activity).name.wrapper
    N = length(z)

    m = model.params.segment.values
    ϵ = diagvalues(model.params.epsilon)
    σ = diagvalues(model.params.sigma)
    α = m.*ϵ./T

    b = m.*di.^3

    q = @. q_i(α, b, m)
    # println(q)
    # println(α)
    # println(b)
    # println(m)

    Σz = sum(z)
    #Iᵢ = @f(Ii,1,_data)
    b̄ = zero(Base.promote_eltype(model,V,T,z))
    mσ³ = zero(b̄)
    A = zero(b̄)
    B = zero(b̄)
    @inbounds for i ∈ @comps
        mᵢ,bᵢ,σᵢ,qᵢ,zᵢ = m[i],b[i],σ[i],q[i],z[i]
        σ³ᵢ = σᵢ*σᵢ*σᵢ
        mσ³ += zᵢ*mᵢ*σ³ᵢ
        b̄ += zᵢ*bᵢ
        A += zᵢ*qᵢ
        B += zᵢ*log(bᵢ)
    end
    mσ³,b̄ = mσ³/Σz,b̄/Σz
    A, B = A/Σz, B/Σz
    gₑ = excess_gibbs_free_energy(model.activity,V,T,z)/(R̄*T*Σz)

    q̄ = gₑ + model.Λ*(log(b̄) - B) +  A
    ᾱ = α_mix(q̄, b̄, m̄)
    # println("g_E/RT = ", gₑ)
    # println("log( b̄ ) = ", log(b̄))
    # println("B = ", B)
    # println("A = ", A)
    # println("q̄ = ", q̄)
    m2ϵσ3₁ = ᾱ*mσ³
    m2ϵσ3₂ = ᾱ*ᾱ*mσ³/m̄

    return m2ϵσ3₁, m2ϵσ3₂
end