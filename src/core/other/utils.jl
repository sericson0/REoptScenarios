function filter_dict_to_match_struct_field_names(d::Dict, s::DataType)
    f = fieldnames(s)
    d2 = Dict()
    for k in f
        if haskey(d, k)
            d2[k] = d[k]
        else
            @warn "dict is missing struct field $k"
        end
    end
    return d2
end
##


function dictkeys_tosymbols(d::Dict)
    d2 = Dict()
    for (k, v) in d
        if k == "loads_kw" && !isempty(v)
            try
                v = convert(Array{Real, 1}, v)
            catch
                @warn "Unable to convert loads_kw to an Array{Real, 1}"
            end
        end
        d2[Symbol(k)] = v
    end
    return d2
end
##

function initialize_defaults(key)
    lib_path = joinpath(dirname(@__FILE__), "..","..","inputs")
    defaults = JSON.parsefile(joinpath(lib_path, "Default_Inputs.json"))
    if !(haskey(defaults, key))
        @warn("No default values for $(key)")
        return Dict()
    else
        return defaults[key]
    end
end
##

#Loads default parameters and adds any tech specific changes
function initialize_with_inputs(input_dic, structure, type_string, tech_specific_changes = nothing, validate_arguments = nothing)
    #Check if PV in inputs
    value_dic = initialize_defaults(type_string)

    if !(haskey(input_dic, type_string)) & (length(value_dic) == 0)
        @warn "Inputs has no instance of $type_string and no default values exist"
        return nothing
    end

    if haskey(input_dic, type_string)
        for (key, val) in input_dic[type_string]
            value_dic[key] = val
        end
    end
    #Allows for additional functions for specific technologies
    if !(tech_specific_changes == nothing)
        value_dic = tech_specific_changes(value_dic, input_dic)
    end

    inputs = filter_dict_to_match_struct_field_names(dictkeys_tosymbols(value_dic), structure)
    instance = structure(;inputs...)

    if !(validate_arguments == nothing)
        validate_arguments(instance)
    end
    return instance
end
##

function npv(rate::Float64, cash_flows::Array)
    npv = cash_flows[1]
    for (y, c) in enumerate(cash_flows[2:end])
        npv += c/(1+rate)^y
    end
    return npv
end
##

function add_element!(outputs, generation, loads, system_state = nothing)
    if length(outputs.gen) > 0
        push!(generation, outputs.gen)
    end
    if length(outputs.load) > 0
        push!(loads, outputs.load)
    end

    if ((system_state != nothing) & haskey(outputs, :system_state))
        for (key, val) in outputs.system_state
            system_state[key] = val
        end
    end
    return outputs.cost
end
