function initialize_system(m, input_file)
    params = Dict()
    input_dic = JSON.parsefile(input_file)
    financial = financial_system(input_dic)
    params["financial"] = financial

    @expression(m, Cost, 0)
    #If technologies not defined then default to pv and storage
    params["system_techs"] = get_system_techs(input_dic)
    #Add technologies
    for tech in params["system_techs"]
        Cost += add_system_technology(tech, m, input_dic, financial, params)
    end

    if haskey(input_dic, "ElectricTariff")
        params["electric_tariff"] = tariff_system(input_dic)
    end

    if haskey(input_dic, "ElectricLoad")
        params["load"] = site_load_system(input_dic["ElectricLoad"])
    end
    params["system_cost"] = Cost

    return params
end


function add_system_technology(tech_name, m, input_dic, financial, sys_params)
    function_name = tech_name * "_system"

    system_fun = getfield(REoptScenarios, Symbol(function_name))
    tech_system = system_fun(m, input_dic, financial)
    sys_params[tech_name] = tech_system.struct_instance
    return tech_system.sys_cost
end


# X = getfield(REoptScenarios, Symbol("pv_system"))
#Returns a list of system technologies to include
function get_system_techs(input_dic)
    system_techs = []
    #Add technologies here
    technologies_to_check = ["PV", "Storage", "Generator"]
    for tech in technologies_to_check
        if haskey(input_dic, tech)
            push!(system_techs, lowercase(tech))
        end
    end
    return system_techs
end
