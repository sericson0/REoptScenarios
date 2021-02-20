
function initialize_parameters(m::JuMP.AbstractModel, input_file::String)
    input_dic = JSON.parsefile(input_file)
    #Creates the dictionary params of parameters
    initialize_parameters(m, input_dic)
end


function initialize_parameters(m::JuMP.AbstractModel, input_dic::Dict)

    params = Dict()
    params["inputs"] = input_dic
    params["defaults"] = load_defaults()
    params["system_techs"] = get_values_to_include(input_dic, "technologies")
    params["system_tariffs"] = get_values_to_include(input_dic, "tariffs")



    params["electric_load"] = site_load(params["inputs"]["ElectricLoad"], "electric_load")
    params["times"] = 1:length(params["electric_load"])

    if haskey(params["inputs"], "HeatingLoad")
        params["heating_load"] = site_load(params["inputs"]["HeatingLoad"], "heating_load")
    end
    if haskey(params["inputs"], "CoolingLoad")
        params["cooling_load"] = site_load(params["inputs"]["CoolingLoad"], "cooling_load")
    end

    params["site"] = initialize_with_inputs(params, params["defaults"], "Site")
    params["financial"] = initialize_with_inputs(params, params["defaults"], "Financial", setup_financial_inputs)

    for tariff_name in params["system_tariffs"]
        params[tariff_name] = add_parameters(tariff_name, params)
    end

    for tech_name in params["system_techs"]
        params[tech_name] = add_parameters(tech_name, params)
    end

    params["scenario"] = initialize_with_inputs(params, params["defaults"], "GridScenario", setup_grid_scenario_inputs)

    params["results"] = Dict()
    return params
end
##
function add_parameters(val_name::String, params::Dict)
    struct_name = get_struct_name(val_name)

    setup_inputs_name = Symbol("setup_" * val_name * "_inputs")
    validate_args_name = Symbol("validate_" * val_name * "_args")
    setup_inputs_fun = isdefined(REoptScenarios, setup_inputs_name) ? getfield(REoptScenarios, setup_inputs_name) : nothing
    validate_args_fun = isdefined(REoptScenarios, validate_args_name) ? getfield(REoptScenarios, validate_args_name) : nothing
    return initialize_with_inputs(params, params["defaults"], struct_name, setup_inputs_fun, validate_args_fun)
end



##
function get_values_to_include(input_dic, folder)
    values_included = []
    values_to_check = replace.(readdir(joinpath(dirname(dirname(@__FILE__)), folder)), ".jl"=>"")
    # technologies_to_check = ["PV", "Storage", "Generator"]
    for val in values_to_check
        if haskey(input_dic, get_struct_name(val))
            push!(values_included, val)
        end
    end
    return values_included
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

function get_struct_name(tech_name::String)
    struct_name = replace(tech_name, "_" => " ")
    if length(struct_name) <= 3
        struct_name = uppercase(struct_name)
    else
        struct_name = titlecase(struct_name)
    end
    struct_name = replace(struct_name, " " => "")
    return struct_name
end
