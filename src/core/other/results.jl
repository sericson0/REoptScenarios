function add_scenario_results(results_dic, scenario, tech_name; gen = nothing, load = nothing, system_state = nothing, cost = nothing, other_results = nothing)
	if scenario.name == ""
		scenario_name = "grid_scenario"
	else
		scenario_name = scenario.name
	end
	results_dic[scenario_name][tech_name] = Dict()
	if !isnothing(gen)
		if length(gen) > 0
			results_dic[scenario_name][tech_name]["generation_total"] = sum(gen)
			results_dic[scenario_name][tech_name]["generation_timeseries"] = gen
		end
	end
	if !isnothing(load)
		if length(load) > 0
			results_dic[scenario_name][tech_name]["load_total"] = sum(load)
			results_dic[scenario_name][tech_name]["load_timeseries"] = load
		end
	end
	if !isnothing(system_state)
		for (key, val) in system_state
			results_dic[scenario_name][tech_name][key*"_total"] = sum(val)
			results_dic[scenario_name][tech_name][key*"_timeseries"] = val
		end
	end
	if !isnothing(cost)
		results_dic[scenario_name][tech_name]["costs"] = cost
	end
	if !isnothing(other_results)
		for (key, value) in other_results
			results_dic[scenario_name][tech_name][key] = value
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


# m = Model(Optimizer_Type)
# x = @variable(m, lower_bound = 0, upper_bound = 3, base_name = "x")
# y = @variable(m, lower_bound = 0, upper_bound = 3, base_name = "y")
# @constraint(m, x+y <= 4)
# @objective(m, Max, x+2y)
# optimize!(m)
# d = Dict("x"=>x, "y"=>y)
