function add_scenario_results(results_dic, scenario, tech_name; grid_connected = true, gen = nothing, load = nothing, system_state = nothing, cost = nothing, other_results = nothing)
	results_folder = grid_connected ? "grid_connected" : "events"

	if scenario.name == ""
		scenario_name = "grid_scenario"
	else
		scenario_name = scenario.name
	end
	results_dic[results_folder][scenario_name][tech_name] = Dict()
	if !isnothing(gen)
		if length(gen) > 0
			results_dic[results_folder][scenario_name][tech_name]["generation_total"] = sum(gen)
			results_dic[results_folder][scenario_name][tech_name]["generation_timeseries"] = gen
		end
	end
	if !isnothing(load)
		if length(load) > 0
			results_dic[results_folder][scenario_name][tech_name]["load_total"] = sum(load)
			results_dic[results_folder][scenario_name][tech_name]["load_timeseries"] = load
		end
	end
	if !isnothing(system_state)
		for (key, val) in system_state
			results_dic[results_folder][scenario_name][tech_name][key*"_total"] = sum(val)
			results_dic[results_folder][scenario_name][tech_name][key*"_timeseries"] = val
		end
	end
	if !isnothing(cost)
		results_dic[results_folder][scenario_name][tech_name]["costs"] = cost
	end
	if !isnothing(other_results)
		for (key, value) in other_results
			results_dic[results_folder][scenario_name][tech_name][key] = value
		end
	end

end


function get_result_values(results; roundto = 3)
	if isa(results, Dict)
		d = Dict()
		for (key, val) in results
			d[key] = get_result_values(val, roundto = roundto)
		end
		return d
	elseif isa(results, JuMP.Containers.DenseAxisArray)
		return_vec = []
		for val in results
			push!(return_vec, get_result_values(val, roundto = roundto))
		end
		return return_vec
	else
		try
			return round(value.(results); digits = roundto)
		catch
			return round(results; digits = roundto)
		end
	end
end
