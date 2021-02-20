function site_load(load_inputs::Dict, load_type = "electric_load")
    if load_type == "electric_load"
        power_ext = "kw"
        energy_ext = "kwh"
    else
        power_ext = "mmbtu"
        energy_ext = "mmbtu"
    end
    #Reads in user defined load or uses commercial building load profile loads
    if haskey(load_inputs, "load_" * power_ext)
        return load_inputs["load_" * power_ext]
    elseif haskey(load_inputs, "buildingtype") && haskey(load_inputs, "city")
        if haskey(load_inputs, "annual_" * energy_ext)
            annual_load = load_inputs["annual_" * energy_ext]
        else
            annual_load = nothing
        end
        return built_in_electric_load(load_inputs["city"], load_inputs["buildingtype"], annual_load, load_type)
    else
        error("Cannot construct ElectricLoad. You must provide either loads_kw or [buildingtype, city].")
    end
end
##

function get_load_scenario(m::JuMP.AbstractModel, scenario::Scenario, params::Dict, load_type = "electric_load")
    load_results_dic = Dict("electric_load" => "electricLoad", "heating_load" => "heatingLoad", "cooling_load" => "coolingLoad")
    #Scenario loads are scaled by load_scaling factor. Note that scenario.times may not be the entire model time (such as for outage events)
    site_load = DenseAxisArray([params[load_type][ts]*scenario.load_scaling for ts in scenario.times], scenario.times)
    add_scenario_results(params["results"], scenario, load_results_dic[load_type]; load = site_load)

    return site_load
end

##

function built_in_electric_load(city::String, buildingtype::String, annual_load::Union{Float64, Nothing}, load_type::String)
    #Helper function to use commercial building load profile loads.
    lib_path = joinpath(dirname(@__FILE__), "..","..", "inputs", "building data")
    default_buildings = vec(readdlm(joinpath(lib_path, "Default_Buildings.dat"), '\n', String, '\n'))
    if !(buildingtype in default_buildings)
        error("buildingtype $(buildingtype) not in $(default_buildings).")
    end
    if load_type == "electric_load"
        load_string = "Load"
    elseif load_type == "heating_load"
        load_string = "Heating"
    elseif  load_type == "cooling_load"
        load_string = "Cooling"
    else
        error("load type $(buildingtype) not in [electric load, heating load, cooling load]")
    end



    if isnothing(annual_load)
        annual_load = JSON.parsefile(joinpath(lib_path, load_type, "Annual_" * load_string * ".json"))[city][lowercase(buildingtype)]
    end

    profile_path = joinpath(lib_path, load_type, string(load_string * "8760_norm_" * city * "_" * buildingtype * ".dat"))
    normalized_profile = vec(readdlm(profile_path, '\n', Float64, '\n'))

    load = [annual_load * ld for ld in normalized_profile]
    return load
end
