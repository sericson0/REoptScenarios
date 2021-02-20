@with_kw mutable struct GridScenario <: Scenario
    name::String
    times::Array{Int64, 1}
    pv_prod_factor_scaling::Float64
    pv_prod_factor::Union{Nothing, Array{Float64, 1}}
    utility_cost_scaling::Float64
    load_scaling::Float64
    scenario_prob::Float64

end
##
function setup_grid_scenario_inputs(val_dic, params)
    if !haskey(val_dic, "pv_prod_factor")
        val_dic["pv_prod_factor"] = nothing
    end
    if !haskey(val_dic, "times")
        val_dic["times"] = params["times"]
    end
    return val_dic
end
##
function initialize_grid_scenarios(m, params, scenario_specific_inputs = nothing)
    # input_dic = JSON.parsefile(input_file)
	params["results"]["grid_connected"] = Dict()
    scenario = initialize_with_inputs(params, params["defaults"], "GridScenario", setup_grid_scenario_inputs)
    Costs = @expression(m, 0)
    system_state = Dict()
    if scenario_specific_inputs == nothing
		if scenario.name == ""
			params["results"]["grid_connected"]["grid_scenario"] = Dict()
		else
			params["results"]["grid_connected"][scenario.name] = Dict()
		end
        Costs += create_scenario(m, scenario::Scenario, params, system_state)
    else
		#Iterate over all potential scenarios
        for (scenario_name, scenario_vals) in scenario_specific_inputs
            setfield!(scenario, Symbol("name"), scenario_name)
            for (key, val) in scenario_vals
                setfield!(scenario, Symbol(key), val)
            end
			params["results"]["grid_connected"][scenario.name] = Dict()
            Costs += create_scenario(m, scenario, params, system_state)
            # println(scenario_name, ": ", Costs)
        end
    end
    return (costs = Costs, system_state = system_state)
end
##

function create_scenario(m, scenario, params, system_state)
    gen_and_load_dic = initiate_gen_and_loads(m, scenario, params)
    costs = 0

    #Add technology dispatch
    for tech_name in params["system_techs"]
        #Loops through each technology, adds the scenario technology (the dispatch), and then adds its relevant elements to the model (load, gen, and state vars) then increase costs by the cost value
        costs += scenario.scenario_prob * add_element!(add_scenario_technology(m, tech_name, scenario, params), gen_and_load_dic, system_state)
    end

	#Grid purchases is variable of purchases from utility. Is input for tairff costs
	grid_purchases = @variable(m, [scenario.times], lower_bound = 0, base_name = "grid_purchases$(scenario.name)")
	add_scenario_results(params["results"], scenario, "grid_purchases"; load = grid_purchases)
    push!(gen_and_load_dic["electric_generation"], grid_purchases)
	# push!(loads, grid_purchases)

	for tariff_name in params["system_tariffs"]
		costs += scenario.scenario_prob * add_element!(add_scenario_tariff(m, tariff_name, grid_purchases, scenario, params), gen_and_load_dic)
	end

	#
    add_load_balance_constraints(m, scenario, gen_and_load_dic)
    return costs
end
##
function add_scenario_technology(m::JuMP.AbstractModel, tech_name::String, scenario::Scenario, params::Dict)
    scenario_fun = getfield(REoptScenarios, Symbol(tech_name * "_scenario"))
    additional_args_fun = getfield(REoptScenarios, Symbol(tech_name * "_args_grid_scenario"))
    return scenario_fun(m, params, scenario, additional_args_fun(m, scenario, params))
end
##

function add_scenario_tariff(m::JuMP.AbstractModel, tariff_name::String, grid_purchases, scenario::Scenario, params::Dict)
    scenario_fun = getfield(REoptScenarios, Symbol(tariff_name * "_scenario"))
    return scenario_fun(m, grid_purchases, scenario, params)
end


##
function add_element!(outputs, gen_and_load_dic, system_state = nothing)
	#Electricity
	#TODO convert from load and gen to electric load
    if haskey(outputs, :gen)
        push!(gen_and_load_dic["electric_generation"], outputs.gen)
    end
    if haskey(outputs, :load)
        push!(gen_and_load_dic["electric_loads"], outputs.load)
    end
	#Heating
	if haskey(outputs, :heating_gen) & haskey(gen_and_load_dic, "heating_generation")
		push!(gen_and_load_dic["heating_generation"], outputs.heating_gen)
	end
	if haskey(outputs, :heating_load) & haskey(gen_and_load_dic, "heating_loads")
		push!(gen_and_load_dic["heating_loads"], outputs.heating_load)
	end
	#Cooling
	if haskey(outputs, :cooling_gen) & haskey(gen_and_load_dic, "cooling_generation")
		push!(gen_and_load_dic["cooling_generation"], outputs.cooling_gen)
	end
	if haskey(outputs, :cooling_load) & haskey(gen_and_load_dic, "cooling_loads")
		push!(gen_and_load_dic["cooling_loads"], outputs.cooling_load)
	end

    if ((system_state != nothing) & haskey(outputs, :system_state))
        for (key, val) in outputs.system_state
            system_state[key] = val
        end
    end
	if haskey(outputs, :cost)
    	return outputs.cost
	else
		return 0
	end
end
##

function initiate_gen_and_loads(m::JuMP.AbstractModel, scenario::Scenario, params::Dict)
	#start with electric load
	gen_and_load_dic = Dict("electric_generation"=>[], "electric_loads" => [])
	push!(gen_and_load_dic["electric_loads"], get_load_scenario(m, scenario, params, "electric_load"))

	if haskey(params, "heating_load")
		gen_and_load_dic["heating_generation"] = []
		gen_and_load_dic["heating_loads"] = []
		push!(gen_and_load_dic["heating_loads"], get_load_scenario(m, scenario, params, "heating_load"))
	end
	if haskey(params, "cooling_load")
		gen_and_load_dic["cooling_generation"] = []
		gen_and_load_dic["cooling_loads"] = []
		push!(gen_and_load_dic["cooling_loads"], get_load_scenario(m, scenario, params, "cooling_load"))
	end
	return gen_and_load_dic
end
##



function add_load_balance_constraints(m::JuMP.AbstractModel, scenario::Scenario, gen_and_load_dic::Dict)
    @constraint(m, [ts in scenario.times], sum([l[ts] for l in gen_and_load_dic["electric_loads"]]) == sum([g[ts] for g in gen_and_load_dic["electric_generation"]]))
	if haskey(gen_and_load_dic, "heating_loads")
		@constraint(m, [ts in scenario.times], sum([l[ts] for l in gen_and_load_dic["heating_loads"]]) == sum([g[ts] for g in gen_and_load_dic["heating_generation"]]))
	end
	if haskey(gen_and_load_dic, "cooling_loads")
		@constraint(m, [ts in scenario.times], sum([l[ts] for l in gen_and_load_dic["cooling_loads"]]) == sum([g[ts] for g in gen_and_load_dic["cooling_generation"]]))
	end

end
