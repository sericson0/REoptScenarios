
function run_reopt(main_input_file, optimizer_type; additional_scenario_inputs = nothing, results_roundto = 3)
    m = Model(optimizer_type)
    params = initialize_parameters(m, main_input_file)


    system = initialize_system(m, params)

    #Check if multiple scenarios inserted
    additional_scenarios_dic = additional_scenario_inputs != nothing ? JSON.parsefile(additional_scenario_inputs) : nothing

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
