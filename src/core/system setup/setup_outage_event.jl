@with_kw mutable struct OutageEvent <: Scenario
    name::String
    system_time_length::Int64
    times::Array{Int64, 1}
    outage_duration_probs::Array{Float64, 1}
    max_outage_duration::Int64
    start_times::Array{Int64, 1}
    start_probs::Array{Float64, 1}
    load_scaling::Float64
    VOLL::Float64
    system_state::Dict
    pv_prod_factor_scaling::Float64
    pv_prod_factor::Union{Nothing, Array{Float64, 1}}
end
##
# initialize_with_inputs(input_dic, structure, type_string, tech_specific_changes = nothing, validate_arguments = nothing)
function setup_outage_event_inputs(val_dic::Dict, params::Dict)
    val_dic["max_outage_duration"] = length(val_dic["outage_duration_probs"])
    val_dic["system_time_length"] = length(params["times"])
    #if there is a 1 hour outage and a 2 hour outage, then there are 2 outages lasting at least 1 hour.
    val_dic["outage_duration_probs"] = cumsum(val_dic["outage_duration_probs"])

    if !haskey(val_dic, "pv_prod_factor")
        val_dic["pv_prod_factor"] = nothing
    end
    if !haskey(val_dic, "start_times")
        val_dic["start_times"] = 1:val_dic["system_time_length"]
    end
    if !haskey(val_dic, "start_probs")
        val_dic["start_probs"] = [1/val_dic["system_time_length"] for i in 1:val_dic["system_time_length"]]
    elseif val_dic["start_probs"] == []
        val_dic["start_probs"] = [1/val_dic["system_time_length"] for i in 1:val_dic["system_time_length"]]
    end
    val_dic["system_state"] = Dict()
    return val_dic
end
##
# input_file = "../test/Inputs/Outage_Test.json"
function initialize_outage_events(m::JuMP.AbstractModel, params::Dict, system_state::Dict)
    event = initialize_with_inputs(params, params["defaults"], "OutageEvent", setup_outage_event_inputs)
    event.system_state = system_state
    #
    main_name = event.name

    Costs = @expression(m, 0)

    for outage_start in event.start_times
        event.name = "$(main_name)_$(outage_start)"
        set_outage_times!(event, outage_start)
        Costs += create_outage_event(m, event, params, outage_start)
    end
    return (costs = Costs, )
end
##
function create_outage_event(m::JuMP.AbstractModel, event::OutageEvent, params::Dict, outage_start::Int)
    generation = []; loads = []; costs = 0

    params["results"][event.name] = Dict()

    for tech in params["system_techs"]
        #Add technologies
        add_element!(add_event_technology(m, tech, event, params, outage_start), generation, loads)
    end

    add_element!(site_load_scenario(m, params, event), generation, loads)
    costs += add_element!(outage_costs(m, params, event, outage_start), generation, loads)
    params["results"][event.name]["outageCost"] = costs
    add_load_balance_constraints(m, event, generation, loads)
    return costs
end
##

function outage_costs(m::JuMP.AbstractModel, params::Dict, event::OutageEvent, outage_start::Int)
    shed_load = @variable(m, [event.times], lower_bound = 0, base_name = "shed_load$(event.name)")
    #Costs are pwf * prob outage starts at t * sum of shed load for each duration d * prob of outage lasting to at least d
    # println("outage start $(outage_start) outage times $(event.times)")
    outage_costs = (params["financial"].pwf_e * event.VOLL * event.start_probs[outage_start] *
                    sum([shed_load[h] * event.outage_duration_probs[d] for (d, h) in enumerate(event.times)]) )
    return (gen = shed_load, load = [], cost = outage_costs)
end
##

function set_outage_times!(event::OutageEvent, start_time::Int)
    time_vals = start_time:(start_time+event.max_outage_duration-1)
    event.times = [((ts - 1) % event.system_time_length) + 1 for ts in time_vals]
end
##

function add_event_technology(m::JuMP.AbstractModel, tech_name::String, event::OutageEvent, params::Dict, outage_start::Int)
    scenario_fun = getfield(REoptScenarios, Symbol(tech_name * "_scenario"))
    additional_args_fun = getfield(REoptScenarios, Symbol(tech_name * "_args_outage_event"))
    return scenario_fun(m, params, event, additional_args_fun(m, event, params, outage_start))
end
