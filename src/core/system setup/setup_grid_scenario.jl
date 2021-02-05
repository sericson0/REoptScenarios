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
    generation = []; loads = []; costs = 0

    #Add technology dispatch
    for tech in params["system_techs"]
        #Loops through each technology, adds the scenario technology (the dispatch), and then adds its relevant elements to the model (load, gen, and state vars)
        #Then increase costs by the cost value
        costs += scenario.scenario_prob * add_element!(add_scenario_technology(tech, m, scenario, params, system_state), generation, loads, system_state)
    end

    add_element!(site_load_scenario(m, params, scenario), generation, loads)

    costs += scenario.scenario_prob * add_element!(grid_costs_scenario(m, params, scenario), generation, loads)
    add_load_balance_constraints(m, scenario, generation, loads)

    return costs
end
##

function add_scenario_technology(tech_name, m, scenario, params, system_state)
    scenario_fun = getfield(REoptScenarios, Symbol(tech_name * "_scenario"))
    additional_args_fun = getfield(REoptScenarios, Symbol(tech_name * "_args_grid_scenario"))
    return scenario_fun(m, params, scenario, additional_args_fun(m, scenario, params))
end
