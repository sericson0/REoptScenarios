using Statistics

@with_kw struct ResourceAdequacy
    energy_pricing::Array{Float64, 1}
    event_start_hours::Dict
    moo_hours::Int64 #Must offer obligation hours (number of event hours)
    lookback_periods::Dict
    monthly_demand_pricing::Array{Float64, 1}
    months_in_program::Array{Int64, 1}
    num_lookback_days::Int64
    baseline_scaling:: Dict
end
##

function setup_resource_adequacy_inputs(value_dic::Dict, params::Dict)
    event_start_hours = Dict(); lookback_periods = Dict(); months_in_program = []

	value_dic["energy_pricing"] = get_energy_prices(value_dic["energy_pricing"])

    for start_hour in value_dic["event_hours"]
        month = Dates.month(Dates.DateTime(2019) + Dates.Hour(start_hour))
        if !haskey(event_start_hours, month)
            event_start_hours[month] = []
            lookback_periods[month] = []
            push!(months_in_program, month)
        end
        push!(event_start_hours[month], start_hour)
        push!(lookback_periods[month], get_lookback_hours(start_hour, value_dic))
    end

    baseline_scaling = Dict()
    #Scales values for lookback period. Is proxy for scaling procedure
    for (month, event_hours_array) in event_start_hours
        if !(value_dic["include_baseline_scaling"])
            baseline_scaling[month] = [1 for i in 1:length(event_hours_array)]
        else
            baseline_scaling[month] = []
            for (index, event_hour) in enumerate(event_hours_array)
                baseline_avg = mean([params[lookback_hour for lookback_hour in lookback_periods[month][index]]])
                push!(baseline_scaling[month], baseline_avg / params["load"][event_hour])
            end
        end
    end
    #
    value_dic["event_start_hours"] = event_start_hours
    value_dic["lookback_periods"] = lookback_periods
    value_dic["months_in_program"] = months_in_program
    value_dic["baseline_scaling"] = baseline_scaling
    return value_dic

end

function resource_adequacy_scenario(m::JuMP.AbstractModel, grid_purchases, scenario::Scenario, params::Dict)
	tariff_return_vals = Dict()
    MaxMonthlyRa = 10000*maximum(params["electric_load"])

	ra = params["resource_adequacy"]

	hourly_ra_reductions = @variable(m, [mth in ra.months_in_program, i in 1:length(ra.event_start_hours[mth]), h in 0:ra.moo_hours-1], base_name = "hourly_ra_reductions$(scenario.name)")
	hourly_reductions_flat = []; event_hours = []; lookback_hours = []
	for mth in ra.months_in_program
		for i in 1:length(ra.event_start_hours[mth])
			for h in 0:ra.moo_hours - 1
				push!(hourly_reductions_flat, hourly_ra_reductions[mth, i, h])
				push!(event_hours, ra.event_start_hours[mth][i] + h)
				for lh in ra.lookback_periods[mth][i] .+ h
					push!(lookback_hours, lh)
				end
			end
		end
	end
	tariff_return_vals["hourlyRaReductions"] = hourly_reductions_flat
	tariff_return_vals["event_hours"] = event_hours
	tariff_return_vals["lookback_hours"] = lookback_hours

	monthly_ra = @variable(m, [mth in ra.months_in_program], base_name = "monthly_ra$(scenario.name)")
	tariff_return_vals["monthlyRa"] = monthly_ra
	#Value of RA for each month
	monthly_ra_value = @variable(m, [mth in ra.months_in_program], base_name = "monthly_ra_value$(scenario.name)")
	bin_ra_participate = @variable(m,[mth in ra.months_in_program], base_name = "bin_ra_participate$(scenario.name)", Bin)

	#Constraints are hourly reductions are equal to the baseline load - event hour load (reductions are indexed by month, event start, and event hourly)
	@constraint(m, [mth in ra.months_in_program, i in 1:length(ra.event_start_hours[mth]), h in 0:ra.moo_hours-1],
			hourly_ra_reductions[mth, i, h] <= calculate_hour_reduction(m, ra, mth, i, h, grid_purchases))

	@constraint(m, [mth in ra.months_in_program, i in 1:length(ra.event_start_hours[mth]), h in 0:ra.moo_hours-1],
			hourly_ra_reductions[mth, i, h] <= calculate_hour_reduction(m, ra, mth, i, h, grid_purchases))
	    #monthly RA is constrained to be the minimum of day average reductions
    @constraint(m, [mth in ra.months_in_program, i in 1:length(ra.event_start_hours[mth])], monthly_ra[mth] <= calculate_average_daily_reduction(m, ra, mth, i, hourly_ra_reductions))

	#Calculate monthly values if RA is acitve
	monthly_ra_dr = @expression(m, [mth in ra.months_in_program], params["financial"].pwf_e * ra.monthly_demand_pricing[mth] * monthly_ra[mth])
	monthly_ra_energy = @expression(m, [mth in ra.months_in_program],
		params["financial"].pwf_e * sum(ra.energy_pricing[ra.event_start_hours[mth][i] + h]*hourly_ra_reductions[mth, i, h] for i in 1:length(ra.event_start_hours[mth]), h in 0:ra.moo_hours-1))

	tariff_return_vals["monthlyRaDr"] = monthly_ra_dr
	tariff_return_vals["monthlyRaEnergy"] = monthly_ra_energy

	#The bin part removes the constraint if the value would be constrained to be negative
	@constraint(m, [mth in ra.months_in_program], monthly_ra_value[mth] <= monthly_ra_dr[mth] + monthly_ra_energy[mth] + (1 - bin_ra_participate[mth]) * MaxMonthlyRa)
	#Constrains to 0 if did not participate
	@constraint(m, [mth in ra.months_in_program], monthly_ra_value[mth] <= bin_ra_participate[mth] * MaxMonthlyRa)
		# @info value(m[:binRaParticipate][7])
    total_ra_value = sum(monthly_ra_value)
	tariff_return_vals["total_ra_value"] = total_ra_value

    add_scenario_results(params["results"], scenario, "resource_adequacy"; cost = -total_ra_value, other_results = tariff_return_vals)
    return (cost = -total_ra_value, )
end


function calculate_hour_reduction(m, ra, month, event_index, hours_from_start, grid_purchases)
	lbst_list = ra.lookback_periods[month][event_index]
	baseline_load = mean(grid_purchases[lbts + hours_from_start] for lbts in lbst_list)
	#baseline loads minus event load
    return (baseline_load - grid_purchases[ra.event_start_hours[month][event_index] + hours_from_start] * ra.baseline_scaling[month][event_index])
end

function calculate_average_daily_reduction(m, ra, month, event_index, hourly_ra_reductions)
    #Take average across event hours
    return mean([hourly_ra_reductions[month, event_index, h] for h in 0:ra.moo_hours-1])
end


function get_lookback_hours(start_hour::Int64, value_dic::Dict)
    lookback_hour_array = []
    potential_lookback_hour = start_hour - 24
    potential_lookback_time = Dates.DateTime(2019) + Dates.Hour(start_hour - 24)

    while length(lookback_hour_array) < value_dic["num_lookback_days"]
        potential_lookback_hour = mod(potential_lookback_hour - 24 - 1, 8760) + 1
        potential_lookback_time = potential_lookback_time - Dates.Hour(24)
        if (potential_lookback_hour in value_dic["event_hours"]) | (Dates.dayofweek(potential_lookback_time) > 5)
            continue
        else
            push!(lookback_hour_array, potential_lookback_hour)
        end
    end
    return lookback_hour_array
end


function get_energy_prices(energy_pricing_inputs)
	if isa(energy_pricing_inputs, Number)
		return [energy_pricing_inputs for _ in 1:8760]
	else
		return value_dic["energy_pricing"]
	end
end
