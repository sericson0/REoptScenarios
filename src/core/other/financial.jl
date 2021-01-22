@with_kw mutable struct Financial
    om_cost_escalation_pct::Float64
    elec_cost_escalation_pct::Float64
    offtaker_tax_pct::Float64
    offtaker_discount_pct::Float64
    two_party_ownership::Bool
    two_party_factor::Float64
    owner_tax_pct::Float64
    owner_discount_pct::Float64
    analysis_years::Int
    macrs_five_year::Array{Float64,1}
    macrs_seven_year::Array{Float64,1}
    pwf_e::Float64
    pwf_om::Float64
end
##
function financial_system(input_dic)
    initialize_with_inputs(input_dic, Financial, "Financial", setup_financial_inputs)
end
##
function setup_financial_inputs(value_dic, input_dic)
    value_dic["pwf_e"] = annuity(
        value_dic["analysis_years"],
        value_dic["elec_cost_escalation_pct"],
        value_dic["offtaker_discount_pct"])

    value_dic["pwf_om"] = annuity(
        value_dic["analysis_years"],
        value_dic["om_cost_escalation_pct"],
        value_dic["owner_discount_pct"])


    if value_dic["two_party_ownership"]
         pwf_offtaker = annuity(value_dic["analysis_years"], 0.0, value_dic["offtaker_discount_pct"])
         pwf_owner = annuity(value_dic["analysis_years"], 0.0, value_dic["owner_discount_pct"])
         two_party_factor = (pwf_offtaker * (1 - value_dic["offtaker_tax_pct"])) /
                            (pwf_owner * (1 - value_dic["owner_tax_pct"]))
     else
         two_party_factor = 1.0
     end
     value_dic["two_party_factor"] = two_party_factor

    return value_dic
end

function annuity(years::Int, rate_escalation::Float64, rate_discount::Float64)
    """
        this formulation assumes cost growth in first period
        i.e. it is a geometric sum of (1+rate_escalation)^n / (1+rate_discount)^n
        for n = 1, ..., years
    """
    x = (1 + rate_escalation) / (1 + rate_discount)
    if x != 1
        pwf = round(x * (1 - x^years) / (1 - x), digits=5)
    else
        pwf = years
    end
    return pwf
end


function levelization_factor(years::Int, rate_escalation::Float64, rate_discount::Float64,
    rate_degradation::Float64)
    #=
    NOTE: levelization_factor for an electricity producing tech is the ratio of:
    - an annuity with an escalation rate equal to the electricity cost escalation rate, starting year 1,
        and a negative escalation rate (the tech's degradation rate), starting year 2
    - divided by an annuity with an escalation rate equal to the electricity cost escalation rate (pwf_e).
    Both use the offtaker's discount rate.
    levelization_factor is multiplied by each use of dvRatedProduction in reopt.jl
        (except dvRatedProduction[t,ts] == dvSize[t] ∀ ts).
    This way the denominator is cancelled in reopt.jl when accounting for the value of energy produced
    since each value constraint uses pwf_e.

    :param analysis_period: years
    :param rate_escalation: escalation rate
    :param rate_discount: discount rate
    :param rate_degradation: positive degradation rate
    :return: present worth factor with escalation (inflation, or degradation if negative)
    NOTE: assume escalation/degradation starts in year 2
    =#
    num = 0
    for yr in range(1, stop=years)
        num += (1 + rate_escalation)^(yr) / (1 + rate_discount)^yr * (1 - rate_degradation)^(yr - 1)
    end
    den = annuity(years, rate_escalation, rate_discount)

    return num/den
end


function effective_cost(;
    itc_basis::Float64,
    replacement_cost::Float64,
    replacement_year::Int,
    discount_rate::Float64,
    tax_rate::Float64,
    itc::Float64,
    macrs_schedule::Array{Float64,1},
    macrs_bonus_pct::Float64,
    macrs_itc_reduction::Float64,
    rebate_per_kw::Float64=0.0,
    )

    """ effective PV and battery prices with ITC and depreciation
        (i) depreciation tax shields are inherently nominal --> no need to account for inflation
        (ii) ITC and bonus depreciation are taken at end of year 1
        (iii) battery replacement cost: one time capex in user defined year discounted back to t=0 with r_owner
        (iv) Assume that cash incentives reduce ITC basis
        (v) Assume cash incentives are not taxable, (don't affect tax savings from MACRS)
        (vi) Cash incentives should be applied before this function into "itc_basis".
             This includes all rebates and percentage-based incentives besides the ITC
    """

    # itc reduces depreciable_basis
    depr_basis = itc_basis * (1 - macrs_itc_reduction * itc)

    # Bonus depreciation taken from tech cost after itc reduction ($/kW)
    bonus_depreciation = depr_basis * macrs_bonus_pct

    # Assume the ITC and bonus depreciation reduce the depreciable basis ($/kW)
    depr_basis -= bonus_depreciation

    # Calculate replacement cost, discounted to the replacement year accounting for tax deduction
    replacement = replacement_cost * (1-tax_rate) / ((1 + discount_rate)^replacement_year)

    # Compute savings from depreciation and itc in array to capture NPV
    tax_savings_array = [0.0]
    for (idx, macrs_rate) in enumerate(macrs_schedule)
        depreciation_amount = macrs_rate * depr_basis
        if idx == 1
            depreciation_amount += bonus_depreciation
        end
        taxable_income = depreciation_amount
        push!(tax_savings_array, taxable_income * tax_rate)
    end

    # Add the ITC to the tax savings
    tax_savings_array[2] += itc_basis * itc

    # Compute the net present value of the tax savings
    tax_savings = npv(discount_rate, tax_savings_array)

    # Adjust cost curve to account for itc and depreciation savings ($/kW)
    cap_cost_slope = itc_basis - tax_savings + replacement - rebate_per_kw

    # Sanity check
    if cap_cost_slope < 0
        cap_cost_slope = 0
    end

    return round(cap_cost_slope, digits=4)
end
