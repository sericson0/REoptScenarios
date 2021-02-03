@with_kw mutable struct Generator
	existing_kw::Real
	min_kw::Real
	max_kw::Real
	cost_per_kw::Real
	om_cost_per_kw::Real
	om_cost_per_kwh::Float64
	fuel_cost_per_gallon::Float64
	fuel_slope_gal_per_kwh::Float64
	fuel_intercept_gal_per_hr::Float64
	fuel_avail_gal::Float64
	min_turndown_pct::Float64  # TODO change this to non-zero value
	only_runs_during_grid_outage::Bool
end
##
#
# function generator_system(m::JuMP.AbstractModel, input_dic::Dict, financial::Financial, results_dic::Dict)
# 	generator = initialize_with_inputs(input_dic, Generator, "Generator")
# 	generator_system(m, generator, financial, results_dic)
# end
# #
function generator_system(m::JuMP.AbstractModel, generator::Generator, params::Dict)
	@variable(m, generator.min_kw  <= dv_generator_kw  <= generator.max_kw)
	cost = generator_cost(m, generator, params["financial"])

	params["results"]["system"]["generator_kw"] = m[:dv_generator_kw]
	params["results"]["system"]["generator_capital_cost"] = cost

	return cost
end
##
function generator_scenario(m::JuMP.AbstractModel, params::Dict, scenario::Scenario, additional_args::NamedTuple)
	# limited_fuel = additional_args.limited_fuel
	#is_outage = additional_args.is_outage
	g = params["generator"]
	Big_M = calculate_generator_bigM(params::Dict)
	#No variables for non outage scenario
	if g.only_runs_during_grid_outage & !(additional_args.is_outage)
		return (gen = [], load = [], cost = 0)
	end

	gen_output = @variable(m, [ts in scenario.times], base_name = "dv_generator_output", lower_bound = 0)


	if g.min_turndown_pct > 0
		bin_gen_is_on = @variable(m, [ts in scenario.times], base_name = "dv_generator_is_on$(scenario.name)", binary = true)
		#Minimum turndown cosntraint
		@constraint(m, [ts in scenario.times], gen_output[ts] >= g.min_turndown_pct*m[:dv_generator_kw] - Big_M * (1- bin_gen_is_on[ts]))
		#Capacity constraint

	elseif g.fuel_intercept_gal_per_hr > 0
		bin_gen_is_on = @variable(m, [ts in scenario.times], base_name = "dv_generator_is_on$(scenario.name)", binary = true)
	else
		bin_gen_is_on = [1.0 for ts in scenario.times]
	end
	#generator output constrained to zero when off and to dv_generator_kw when on.
	@constraint(m, [ts in scenario.times], gen_output[ts] <= m[:dv_generator_kw])
	@constraint(m, [ts in scenario.times], gen_output[ts] <= Big_M * bin_gen_is_on[ts])
	fuel_use = @expression(m, g.fuel_slope_gal_per_kwh * gen_output[ts] + g.fuel_intercept_gal_per_hr * bin_gen_is_on[ts] for ts in scenario.times)

	generation_cost = sum(fuel_use)*g.fuel_cost_per_gallon + sum(gen_output)*g.om_cost_per_kwh

	if additional_args.limited_fuel
		#limited fuel for outage scenario
		fuel_times = [[t0] ; scenario.times]
		fuel_remaining = @variable(m, [ts in fuel_times], base_name = "dv_fuel_remaining$(scenario.name)", lower_bound = 0)
		@constraint(m, fuel_remaining[t0] == g.fuel_avail_gal)
		@constraint(m, [ts in scenario.times], fuel_remaining[ts] == fuel_remaining[ts-1] - fuel_use[ts])


		add_scenario_results(results_dic, scenario, "generator"; gen = gen_output, system_state = Dict("fuelRemaining"=>fuel_remaining), cost = generation_cost)
		return (gen = gen_output, load = [], cost = generation_cost, system_state = Dict("dv_fuel_remaining"=>fuel_remaining))
	else
		add_scenario_results(params["results"], scenario, "generator"; gen = gen_output, cost = generation_cost)
		return (gen = gen_output, load = [], cost = generation_cost)
	end
end
##
function generator_args_grid_scenario(m::JuMP.AbstractModel, scenario::GridScenario, sys_params::Dict)
	#No limited fuel for grid scenario
	return (limited_fuel = false, is_outage = false)
end
##
function generator_args_outage_event(m::JuMP.AbstractModel, event::OutageEvent, sys_params::Dict, outage_start::Int)
	#Limited fuel for outage event
	return (limited_fuel = true, is_outage = true)
end
##

function generator_cost(m::JuMP.AbstractModel, generator::Generator, financial::Financial)
	effective_cost_per_kw = effective_cost(
		itc_basis = generator.cost_per_kw,
		replacement_cost = 0.0,
		replacement_year = financial.analysis_years,
		discount_rate = financial.owner_discount_pct,
		tax_rate = financial.owner_tax_pct,
		itc = 0.0,
		macrs_schedule = financial.macrs_seven_year,
        macrs_bonus_pct= 0.0,
        macrs_itc_reduction = 0.0,
        rebate_per_kw = 0.0
	)
	capital_costs = effective_cost_per_kw * m[:dv_generator_kw]
	om_costs = financial.pwf_om * generator.om_cost_per_kw * m[:dv_generator_kw] * (1-financial.owner_tax_pct)
	return financial.two_party_factor * (capital_costs + om_costs)
end
##
function calculate_generator_bigM(params::Dict)
	return 2*maximum(params["load"])
end
