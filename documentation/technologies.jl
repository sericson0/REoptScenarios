#Replace TECH (tech) with technology name. The struct is uppercase and all others are lowercase
#TECH struct contains system parameters

@with_kw mutable struct TECH #This is uppercase
      min_kw::Float64
      max_kw::Float64
      cost_per_kw::Float64
      om_cost_per_kw::Float64
	  #Other parameters
end
##
#setup_tech_inputs sets up inputs for the struct parameters
#setup_tech_inputs outputs a dictionary of values. Every parameter of the struct must have
#a key in the dictionary, though added keys may be present.
#I.e., if the struct parameters are A, and B, then a valid output of setup_tech_inputs is
# Dict(A => 2, B => 3.5, C = false) but an invalid output is Dict(A => 2) [needs B]
function setup_tech_inputs(value_dic::Dict, params::Dict)
	#Value dict is a dictionary of tech-specific inputs.
	#Run technology specific functions here to create values and save them in value_dic
    return value_dic
end



##
#tech_system adds system size and capital costs to mdoel
function TECH_system(m::JuMP.AbstractModel, tech::TECH, params::Dict)
    @variable(m, tech.min_kw <= dv_tech_kw <= tech.max_kw)
	#Any other sizes such as kWh go here

    cost = tech_cost(m, tech, params["financial"])

	#Adds sizes and capital costs to results
	params["results"]["system"]["tech_kw"] = m[:dv_tech_kw]
	params["results"]["system"]["tech_capital_cost"] = cost
    return cost
end
##
#Tech scenario is dispatch function. Is used for both grid_connected and outage scenarios
function tech_scenario(m::JuMP.AbstractModel, params::Dict, scenario::Scenario, other_arguments)
	#Other arguments is a single or tuple of other arguments i.e., cannot have multiple additional arguments

	#tech_output is a timeseries variable of production
	tech_output = @variable(m, [scenario.times], base_name = "dv_tech_output$(scenario.name)")

    #Dispatch constraints go here
    @constraint(m, [ts in scenario.times], tech_output[ts] <= m[:dv_tech_kw])
	#If the technology uses load (such as battery charging), or has productio costs,
	#Then these should be implemented here as well, and the outputs will be changed.
	#All add_scenario_results potential inputs are
	# add_scenario_results(results_dic, scenario, tech_name; gen = nothing, load = nothing, system_state = nothing, cost = nothing, other_results = nothing)
	add_scenario_results(params["results"], scenario, "tech"; gen = tech_output)
    return (gen = tech_output, load = [], cost = 0)
end

##
#tech_cost calculates the capital cost of the system taking into account taxes, depreciation, and the present worth of O&M costs
#Need to add relevant tech values to struct if used
function tech_cost(m::JuMP.AbstractModel, tech::tech, financial::Financial)
    effective_cost_per_kw = effective_cost(;
                itc_basis= tech.cost_per_kw,
                replacement_cost= 0.0,
                replacement_year= financial.analysis_years,
                discount_rate= financial.owner_discount_pct,
                tax_rate= financial.owner_tax_pct,
                itc= tech.total_itc_pct,
                macrs_schedule = tech.macrs_option_years == 7 ? financial.macrs_seven_year : financial.macrs_five_year,
                macrs_bonus_pct= tech.macrs_bonus_pct,
                macrs_itc_reduction = tech.macrs_itc_reduction,
                rebate_per_kw = tech.total_rebate_per_kw
            )
    capital_costs = effective_cost_per_kw * m[:dv_tech_kw]
    om_costs = financial.pwf_om * tech.om_cost_per_kw * m[:dv_tech_kw] * (1-financial.owner_tax_pct)
    return financial.two_party_factor * (capital_costs + om_costs)
end
##

function validate_tech_args(tech::Tech)
 #Validate struct parameters. Code is optional
end


##
function tech_args_grid_scenario(m::JuMP.AbstractModel, scenario::GridScenario, params::Dict)
	#Code to calculate additional inputs to the technology dispatch during grid scenarios
	#If no additional arguments then return nothing
	return nothing
end
##

function tech_args_outage_event(m::JuMP.AbstractModel, event::OutageEvent, params::Dict, outage_start::Int)
	#Code to calculate additional inputs to the technology dispatch during outage events
	#If no additional arguments then return nothing
	return nothing
end
