
function run_reopt(main_inputs::Union{String, Dict}, optimizer_type; additional_scenario_inputs = nothing, results_roundto = 3)
    m = Model(optimizer_type)
    params = initialize_parameters(m, main_inputs)


    system = initialize_system(m, params)

    #Check if multiple scenarios inserted
    if additional_scenario_inputs == nothing
        additional_scenarios_dic = nothing
    elseif isa(additional_scenario_inputs, Dict)
        additional_scenarios_dic = additional_scenario_inputs
    elseif isa(additional_scenario_inputs, String)
        additional_scenarios_dic = JSON.parsefile(additional_scenario_inputs)
    else
        println("Must input nothing, dictionary, or script to additional scenario inputs. Not using additional scenario inputs in run")
        additional_scenarios_dic = nothing
    end

    grid_scenario = initialize_grid_scenarios(m, params, additional_scenarios_dic)

    if haskey(params["inputs"], "OutageEvent")
        #TODO Would have to update to incorporate outages for different types of state variables
        outage_events = initialize_outage_events(m, params, Dict("dv_stored_energy"=>grid_scenario.system_state["dv_stored_energy"]))
    else
        outage_events = (costs = 0, )
    end

    @objective(m, Min, system.costs + grid_scenario.costs + outage_events.costs)
    optimize!(m)

    results = get_result_values(params["results"]; roundto = results_roundto)
    results["LCC"] = round(objective_value(m); digits =  2)
    results["parameters"] = params
    return results
end
