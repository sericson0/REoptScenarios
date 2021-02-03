
function initialize_parameters(m::JuMP.AbstractModel, input_file::String)
    #Creates the dictionary params of parameters
    input_dic = JSON.parsefile(input_file)

    params = Dict()
    params["inputs"] = input_dic
    params["defaults"] = load_defaults()
    params["system_techs"] = get_system_techs(input_dic)

    params["load"] = site_load(params["inputs"]["ElectricLoad"])
    params["times"] = 1:length(params["load"])

    params["site"] = initialize_with_inputs(params, params["defaults"], "Site")
    params["financial"] = initialize_with_inputs(params, params["defaults"], "Financial", setup_financial_inputs)

    if haskey(params["inputs"], "ElectricTariff")
        params["electric_tariff"] = initialize_with_inputs(params, params["defaults"], "ElectricTariff", setup_electricity_tariff_inputs)
    end

    for tech_name in params["system_techs"]
        #TODO This could be done better. Gets at PV being all uppercase
        if length(tech_name) <= 3
            struct_name = uppercase(tech_name)
        else
            struct_name = uppercasefirst(tech_name)
        end

        setup_inputs_name = Symbol("setup_"*tech_name*"_inputs")
        validate_args_name = Symbol("validate_"*tech_name*"_args")
        setup_inputs_fun = isdefined(REoptScenarios, setup_inputs_name) ? getfield(REoptScenarios, setup_inputs_name) : nothing
        validate_args_fun = isdefined(REoptScenarios, validate_args_name) ? getfield(REoptScenarios, validate_args_name) : nothing

        params[tech_name] = initialize_with_inputs(params, params["defaults"], struct_name, setup_inputs_fun, validate_args_fun)
    end


    params["scenario"] = initialize_with_inputs(params, params["defaults"], "GridScenario", setup_grid_scenario_inputs)

    params["results"] = Dict()
    return params
end
##
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
##

function load_defaults()
    lib_path = joinpath(dirname(@__FILE__), "..","..","inputs")
    defaults = JSON.parsefile(joinpath(lib_path, "Default_Inputs.json"))
    return defaults
end
##
function get_defaults(defaults, type_string)
    if !(haskey(defaults, type_string))
        @warn("No default values for $(key)")
        return Dict()
    else
        return deepcopy(defaults[type_string])
    end
end
##

#Loads default parameters and adds any tech specific changes
function initialize_with_inputs(params, defaults, type_string, specific_changes = nothing, validate_arguments = nothing)
    inputs = params["inputs"]
    structure = getfield(REoptScenarios, Symbol(type_string))

    value_dic = get_defaults(defaults, type_string)

    if !(haskey(inputs, type_string)) & (length(value_dic) == 0)
        @warn "Inputs has no instance of $type_string and no default values exist"
        return Dict()
    end

    if haskey(inputs, type_string)
        for (key, val) in inputs[type_string]
            value_dic[key] = val
        end
    end
    #Allows for additional functions for specific changes
    if !(specific_changes == nothing)
        value_dic = specific_changes(value_dic, params)
    end

    struct_inputs = filter_dict_to_match_struct_field_names(dictkeys_tosymbols(value_dic), structure)
    struct_instance = structure(;struct_inputs...)

    if validate_arguments != nothing
        validate_arguments(struct_instance)
    end
    return struct_instance
end
