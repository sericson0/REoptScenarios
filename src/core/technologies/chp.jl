
@with_kw mutable struct CHP
      min_kw::Float64
      max_kw::Float64
      cost_per_kw::Float64
      om_cost_us_dollars_per_kw::Float64
	  om_cost_us_dollars_per_kwh::Float64
	  om_cost_us_dollars_per_hr_per_kw_rated::Float64
	  min_turn_down_pct::Float64
	  min_allowable_kw::Float64
	  chp_power_derate::Array{Float64, 1}
	  max_derate_factor::Float64
	  derate_start_temp_degF::Float64
	  derate_slope_pct_per_degF::Float64
	  # chp_unavailability_periods::Array{Int64, 1}
	  cooling_thermal_factor::Float64
	  prime_mover::String
	  size_class::Int64
	  #
	  fuel_burn_slope::Float64
	  fuel_burn_intercept::Float64
	  thermal_prod_slope::Float64
	  thermal_prod_intercept::Float64
	  fuel_rate_dollars_per_mmbtu::Array{Float64, 1} #hourly
	  #
	  total_itc_pct::Float64
	  macrs_itc_reduction::Float64
	  macrs_bonus_pct::Float64
	  macrs_option_years::Int64
	  chp_fuel_escalation_pct::Float64
end





##
function setup_chp_inputs(value_dic::Dict, params::Dict)
	if value_dic["use_chp_defaults"]
		prime_mover = value_dic["prime_mover"]
		if haskey(value_dic, "size_class")
			size_class = value_dic["size_class"]
		else
			size_class = 1
		end
		chp_defaults = JSON.parsefile(joinpath(dirname(@__FILE__), "..","..", "inputs", "chp_default_data.json"))[prime_mover]
		#TODO add cost segments
		value_dic["cost_per_kw"] = chp_defaults["installed_cost_us_dollars_per_kw"][size_class][2]
		for val in ["elec_effic_half_load", "om_cost_us_dollars_per_kw", "om_cost_us_dollars_per_kwh", "om_cost_us_dollars_per_hr_per_kw_rated",
					"elec_effic_full_load", "elec_effic_half_load", "min_allowable_kw", "cooling_thermal_factor", "min_kw", "max_kw", "min_turn_down_pct",
					"max_derate_factor", "derate_start_temp_degF", "derate_slope_pct_per_degF"]
			value_dic[val] = chp_defaults[val][size_class]
		end
		hw_or_steam_index_dict = Dict("hot_water"=> 1, "steam"=> 2)
		if haskey(value_dic, "hw_or_steam")
			hw_or_steam = hw_or_steam_index_dict[value_dic["hw_or_steam"]]
		else
			hw_or_steam = hw_or_steam_index_dict[chp_defaults["default_boiler_type"]]
		end
		value_dic["thermal_effic_full_load"] = chp_defaults["thermal_effic_full_load"][hw_or_steam][size_class]
		value_dic["thermal_effic_half_load"] = chp_defaults["thermal_effic_half_load"][hw_or_steam][size_class]

	end
	#
	fuel_burn_full_load = 1 / value_dic["elec_effic_full_load"] * 3412.0 / 1.0E6 * 1.0  # [MMBtu/hr/kW]
	fuel_burn_half_load = 1 / value_dic["elec_effic_half_load"] * 3412.0 / 1.0E6 * 1.0  # [MMBtu/hr/kW]
	value_dic["fuel_burn_slope"] = (fuel_burn_full_load - fuel_burn_half_load) / (1.0 - 0.5)  # [MMBtu/hr/kW]
	value_dic["fuel_burn_intercept"] = fuel_burn_full_load - value_dic["fuel_burn_slope"] # [MMBtu/hr/kW_rated]

	#Not sure where the 3412/1E6 comes from.
	thermal_prod_full_load = 1.0 * 1 / value_dic["elec_effic_full_load"] * value_dic["thermal_effic_full_load"] * 3412.0 / 1.0E6  # [MMBtu/hr/kW]
	thermal_prod_half_load = 0.5 * 1 / value_dic["elec_effic_half_load"] * value_dic["thermal_effic_half_load"] * 3412.0 / 1.0E6   # [MMBtu/hr/kW]
	value_dic["thermal_prod_slope"] = (thermal_prod_full_load - thermal_prod_half_load) / (1.0 - 0.5)  # [MMBtu/hr/kW]
	value_dic["thermal_prod_intercept"] = thermal_prod_full_load - value_dic["thermal_prod_slope"] # [MMBtu/hr/kW_rated]


	#TODO add chp_unavailability_hourly_list
	value_dic["elec_prod_factor"] = [1.0 for _ in 1:8760]
	value_dic["thermal_prod_factor"] = [1.0 for _ in 1:8760]

	if length(value_dic["fuel_rate_dollars_per_mmbtu"]) == 1
		value_dic["fuel_rate_dollars_per_mmbtu"] = [value_dic["fuel_rate_dollars_per_mmbtu"] for _ in 1:8760]
	elseif length(value_dic["fuel_rate_dollars_per_mmbtu"]) == 12
		days_in_month = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
		new_val = []
		for (m, d) in enumerate(days_in_month)
			append!(new_val, repeat([value_dic["fuel_rate_dollars_per_mmbtu"][m]], 24*d))
			value_dic["fuel_rate_dollars_per_mmbtu"] = new_val
		end
	end

	if !haskey(value_dic, "chp_power_derate")
		value_dic["chp_power_derate"] = [1.0 for _ in 1:8760]
	end
    return value_dic
end


##
#chp_system adds system size and capital costs to mdoel
function chp_system(m::JuMP.AbstractModel, chp::CHP, params::Dict)
    @variable(m, chp.min_kw <= dv_chp_kw <= chp.max_kw)
	#Any other sizes such as kWh go here

    cost = chp_cost(m, chp, params["financial"])

	#Adds sizes and capital costs to results
	params["results"]["system"]["chp_kw"] = m[:dv_chp_kw]
	params["results"]["system"]["chp_capital_cost"] = cost
    return cost
end
##
function chp_scenario(m::JuMP.AbstractModel, params::Dict, scenario::Scenario, fuel_cost_multiplier = 1.0)
	#Other arguments is a single or tuple of other arguments i.e., cannot have multiple additional arguments
	chp = params["chp"]
	Big_M = calculate_chp_bigM(params)



	bin_chp_is_on = @variable(m, [scenario.times], base_name = "bin_chp_is_on$(scenario.name)", binary = true)
	#Electric
	chp_electric_output = @variable(m, [scenario.times], base_name = "dv_chp_electric_output$(scenario.name)", lower_bound = 0)
	@constraint(m, [ts in scenario.times], chp_electric_output[ts] <= m[:dv_chp_kw])
	@constraint(m, [ts in scenario.times], chp_electric_output[ts] <= Big_M * bin_chp_is_on[ts])
	@constraint(m, [ts in scenario.times], chp_electric_output[ts] >= m[:dv_chp_kw] * chp.min_turn_down_pct - Big_M * (1 - bin_chp_is_on[ts]))	#Min turndown constraint
	#Thermal
	chp_thermal_output = @variable(m, [scenario.times], base_name = "dv_chp_thermal_output$(scenario.name)", lower_bound = 0)
	#TODO Change constraints and solve feasibility problems
	# chp_thermal_y_int = @variable(m, [scenario.times], base_name = "dv_chp_thermal_y_int$(scenario.name)")
	# @constraint(m, [ts in scenario.times], chp_thermal_y_int[ts] <= chp.thermal_prod_intercept * m[:dv_chp_kw])
	# @constraint(m, [ts in scenario.times], chp_thermal_y_int[ts] <= Big_M * chp.thermal_prod_slope * bin_chp_is_on[ts])
	# @constraint(m, [ts in scenario.times], chp_thermal_y_int[ts] >= chp.thermal_prod_intercept * m[:dv_chp_kw] - Big_M * chp.thermal_prod_slope  * (1 - bin_chp_is_on[ts]))
	# @constraint(m, [ts in scenario.times], chp_thermal_output[ts] == chp.thermal_prod_slope * chp_electric_output[ts] + chp_thermal_y_int[ts])
	#
	#Temporary constraint
	@constraint(m, [ts in scenario.times], chp_thermal_output[ts] <= chp.thermal_prod_slope * m[:dv_chp_kw])

	#Fuel use
	chp_fuel_y_int = @variable(m, [scenario.times], base_name = "dv_chp_fuel_y_int$(scenario.name)", lower_bound = 0)
	chp_fuel_usage = @variable(m, [scenario.times], base_name = "dv_chp_fuel_useage$(scenario.name)")

	@constraint(m, [ts in scenario.times], chp_fuel_usage[ts]  == chp_fuel_y_int[ts] + chp.fuel_burn_slope * chp_electric_output[ts])
	#Constraint (1d): Y-intercept fuel burn for CHP
	@constraint(m, [ts in scenario.times], chp.fuel_burn_intercept * m[:dv_chp_kw] - Big_M * (1-bin_chp_is_on[ts]) <= chp_fuel_y_int[ts])

	operating_costs = calculate_operating_costs(m, chp, params["financial"], scenario, chp_electric_output, chp_fuel_usage, bin_chp_is_on, fuel_cost_multiplier)

	add_scenario_results(params["results"], scenario, "chp"; gen = chp_electric_output, cost = operating_costs, system_state = Dict("CHPfuelUse"=>chp_fuel_usage, "CHPthermalGen"=>chp_thermal_output, "CHPhoursOn" => bin_chp_is_on))
    return (gen = chp_electric_output, heating_gen = chp_thermal_output, cost = operating_costs)
end

##
#chp_cost calculates the capital cost of the system taking into account taxes, depreciation, and the present worth of O&M costs
#Need to add relevant chp values to struct if used
function chp_cost(m::JuMP.AbstractModel, chp::CHP, financial::Financial)
    effective_cost_per_kw = effective_cost(;
                itc_basis= chp.cost_per_kw,
                replacement_cost= 0.0,
                replacement_year= financial.analysis_years,
                discount_rate= financial.owner_discount_pct,
                tax_rate= financial.owner_tax_pct,
                itc= chp.total_itc_pct,
                macrs_schedule = chp.macrs_option_years == 7 ? financial.macrs_seven_year : financial.macrs_five_year,
                macrs_bonus_pct= chp.macrs_bonus_pct,
                macrs_itc_reduction = chp.macrs_itc_reduction,
                # rebate_per_kw = chp.total_rebate_per_kw
                rebate_per_kw = 0.0
            )
    capital_costs = effective_cost_per_kw * m[:dv_chp_kw]
    om_costs = financial.pwf_om * chp.om_cost_us_dollars_per_kw * m[:dv_chp_kw] * (1-financial.owner_tax_pct)
    return financial.two_party_factor * (capital_costs + om_costs)
end
##
# function validate_chp_args(chp::CHP)
#  #Validate struct parameters. Code is optional
# end
##
function chp_args_grid_scenario(m::JuMP.AbstractModel, scenario::GridScenario, params::Dict)
	#Code to calculate additional inputs to the chpnology dispatch during grid scenarios
	#If no additional arguments then return nothing
	return 1.0
end
##

function chp_args_outage_event(m::JuMP.AbstractModel, event::OutageEvent, params::Dict, outage_start::Int)
	#Code to calculate additional inputs to the chpnology dispatch during outage events
	#If no additional arguments then return nothing
	return nothing
end


function calculate_chp_bigM(params::Dict)
	return 10*maximum(params["electric_load"])
end



function calculate_operating_costs(m::JuMP.AbstractModel, chp::CHP, financial::Financial, scenario::Scenario, chp_electric_output, chp_fuel_usage, bin_chp_is_on, fuel_cost_multiplier)
	#
	fuel_pwf = levelization_factor(financial.analysis_years, chp.chp_fuel_escalation_pct, financial.owner_discount_pct, 0.0)
	fuel_costs = fuel_pwf * (1 - financial.owner_tax_pct) * sum([chp_fuel_usage[ts] * chp.fuel_rate_dollars_per_mmbtu[ts] for ts in scenario.times]) * fuel_cost_multiplier
	om_costs = financial.pwf_om * (1 - financial.owner_tax_pct) * chp.om_cost_us_dollars_per_kwh * sum(chp_electric_output)
	hours_run_costs = chp.om_cost_us_dollars_per_hr_per_kw_rated * sum(bin_chp_is_on) * m[:dv_chp_kw]

	return fuel_costs + om_costs + hours_run_costs
end
