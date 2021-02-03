@with_kw mutable struct Storage
    min_kw::Float64
    max_kw::Float64
    min_kwh::Float64
    max_kwh::Float64
    internal_efficiency_pct::Float64
    inverter_efficiency_pct::Float64
    rectifier_efficiency_pct::Float64
    soc_min_pct::Float64
    soc_init_pct::Float64
    can_grid_charge::Bool
    can_grid_export::Bool
    cost_per_kw::Float64
    cost_per_kwh::Float64
	om_cost_per_kw::Float64
    replace_cost_per_kw::Float64
    replace_cost_per_kwh::Float64
    inverter_replacement_year::Int
    battery_replacement_year::Int
    macrs_option_years::Int
    macrs_bonus_pct::Float64
    macrs_itc_reduction::Float64
    total_itc_pct::Float64
    total_rebate_per_kw::Float64
end
##
function storage_system(m::JuMP.AbstractModel, storage::Storage, params::Dict)

	#Includes Constraint (4b) lower and upper bounds on storage energy capacity
	@variable(m, storage.min_kwh  <= dv_storage_kwh  <= storage.max_kwh)
	#Includes Constraint (4c) lower and upper bounds on storage power capacity
	@variable(m, storage.min_kw <= dv_storage_kw <= storage.max_kw)

	cost = storage_cost(m, storage, params["financial"])

	params["results"]["system"]["storage_kw"] = m[:dv_storage_kw]
	params["results"]["system"]["storage_kwh"] = m[:dv_storage_kwh]
	params["results"]["system"]["storage_capital_cost"] = cost

	return cost
end
##
function storage_scenario(m::JuMP.AbstractModel, params::Dict, scenario::Scenario, initial_charge)
	t0 = scenario.times[1] - 1
	#stored energy values and initial constraint
	stored_energy_times = [[t0] ; scenario.times]
	stored_energy = @variable(m, [ts in stored_energy_times], base_name = "dv_stored_energy$(scenario.name)")

	@constraint(m, stored_energy[t0] == initial_charge)
	#Constraint (4j): Minimum state of charge
	@constraint(m, [ts in scenario.times], params["storage"].soc_min_pct * m[:dv_storage_kwh] <= stored_energy[ts])
	#Constraint (4n): Maximum state of charge
	@constraint(m, [ts in scenario.times], stored_energy[ts] <= m[:dv_storage_kwh])

	#Storage charge and discharge variables
	charge = @variable(m, [scenario.times], base_name = "dv_storage_charge$(scenario.name)", lower_bound = 0)

    discharge = @variable(m, [scenario.times], base_name = "dv_storage_discharge$(scenario.name)", lower_bound = 0)


	# Constraint (4g): state-of-charge for electrical storage
	charge_efficiency    = params["storage"].rectifier_efficiency_pct * params["storage"].internal_efficiency_pct^0.5
	discharge_efficiency = params["storage"].inverter_efficiency_pct * params["storage"].internal_efficiency_pct^0.5
	@constraint(m, [ts in 1:length(scenario.times)],
		#TODO This is ugly but does for the moment
        stored_energy[scenario.times[ts]] == stored_energy[stored_energy_times[ts]] + charge_efficiency * charge[scenario.times[ts]] - discharge[scenario.times[ts]] / discharge_efficiency)

	# charging is no greater than power capacity
	@constraint(m, [ts in scenario.times], charge[ts] <= m[:dv_storage_kw])

	# Constraint discharge is no greater than power capacity
	@constraint(m, [ts in scenario.times], discharge[ts] <= m[:dv_storage_kw])


	add_scenario_results(params["results"], scenario, "storage"; gen = discharge, load = charge, system_state = Dict("storedEnergy"=>stored_energy))
	return (gen = discharge, load = charge, cost = 0, system_state = Dict("dv_stored_energy"=>stored_energy))
end
##
function storage_cost(m::JuMP.AbstractModel, storage::Storage, financial::Financial)
	effective_cost_per_kw = effective_cost(
		itc_basis = storage.cost_per_kw,
		replacement_cost = storage.replace_cost_per_kw,
		replacement_year = storage.inverter_replacement_year,
		discount_rate = financial.owner_discount_pct,
		tax_rate = financial.owner_tax_pct,
		itc = storage.total_itc_pct,
		macrs_schedule = storage.macrs_option_years == 7 ? financial.macrs_seven_year : financial.macrs_five_year,
        macrs_bonus_pct= storage.macrs_bonus_pct,
        macrs_itc_reduction = storage.macrs_itc_reduction,
        rebate_per_kw = storage.total_rebate_per_kw
	)
	effective_cost_per_kwh = effective_cost(
		itc_basis = storage.cost_per_kwh,
		replacement_cost = storage.replace_cost_per_kwh,
		replacement_year = storage.inverter_replacement_year,
		discount_rate = financial.owner_discount_pct,
		tax_rate = financial.owner_tax_pct,
		itc = storage.total_itc_pct,
		macrs_schedule = storage.macrs_option_years == 7 ? financial.macrs_seven_year : financial.macrs_five_year,
		macrs_bonus_pct = storage.macrs_bonus_pct,
		macrs_itc_reduction = storage.macrs_itc_reduction,
		rebate_per_kw = 0.0
	)

	capital_costs = effective_cost_per_kw * m[:dv_storage_kw] + effective_cost_per_kwh * m[:dv_storage_kwh]
	om_costs = financial.pwf_om * storage.om_cost_per_kw * m[:dv_storage_kw] * (1-financial.owner_tax_pct)
	return financial.two_party_factor * (capital_costs + om_costs)
end
##
function storage_args_grid_scenario(m::JuMP.AbstractModel, scenario::GridScenario, sys_params::Dict)
	#Returns initial charge
	return m[:dv_storage_kwh] * sys_params["storage"].soc_init_pct
end
##
function storage_args_outage_event(m::JuMP.AbstractModel, event::OutageEvent, sys_params::Dict, outage_start::Int)
	#Returns initial charge for outage event
	return event.system_state["dv_stored_energy"][outage_start-1]
end
##
