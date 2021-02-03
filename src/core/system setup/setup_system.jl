function initialize_system(m::JuMP.AbstractModel, params::Dict)
    params["results"]["system"] = Dict()
    @expression(m, System_Costs, 0)
    #If technologies not defined then default to pv and storage
    #Add technologies
    for tech in params["system_techs"]
        System_Costs += add_system_technology(m, tech, params)
    end

    return (costs = System_Costs, )
end

function add_system_technology(m::JuMP.AbstractModel, tech_name::String, params::Dict)
    system_fun = getfield(REoptScenarios, Symbol(tech_name * "_system"))
    system_cost = system_fun(m, params[tech_name], params)
    return system_cost
end
# X = getfield(REoptScenarios, Symbol("pv_system"))
