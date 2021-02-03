function site_load(load_inputs::Dict)
    #Reads in user defined load or uses commercial building load profile loads
    if haskey(load_inputs, "load_kw")
        return load_inputs["load_kw"]
    elseif haskey(load_inputs, "buildingtype") && haskey(load_inputs, "city")
        if haskey(load_inputs, "annual_kwh")
            annual_kwh = load_inputs["annual_kwh"]
        else
            annual_kwh = nothing
        end
        return built_in_electric_load(load_inputs["city"], load_inputs["buildingtype"], annual_kwh)
    else
        error("Cannot construct ElectricLoad. You must provide either loads_kw or [buildingtype, city].")
    end
end
##

function site_load_scenario(m::JuMP.AbstractModel, params::Dict, scenario::Scenario)
    #Scenario loads are scaled by load_scaling factor. Note that scenario.times may not be the entire model time (such as for outage events)
    site_load = DenseAxisArray([params["load"][ts]*scenario.load_scaling for ts in scenario.times], scenario.times)
    add_scenario_results(params["results"], scenario, "load"; load = site_load)
    return (load = site_load, gen = [], cost = 0)
end
##

function add_load_balance_constraints(m::JuMP.AbstractModel, scenario::Scenario, generation::Array, loads::Array)
    @constraint(m, [ts in scenario.times], sum([l[ts] for l in loads]) <= sum([g[ts] for g in generation]))
end
##

function built_in_electric_load(city::String, buildingtype::String, annual_kwh::Union{Float64, Nothing})
    #Helper function to use commercial building load profile loads.
    lib_path = joinpath(dirname(@__FILE__), "..","..", "inputs", "building data")
    default_buildings = vec(readdlm(joinpath(lib_path, "Default_Buildings.dat"), '\n', String, '\n'))
    if !(buildingtype in default_buildings)
        error("buildingtype $(buildingtype) not in $(default_buildings).")
    end

    if isnothing(annual_kwh)
        annual_kwh = JSON.parsefile(joinpath(lib_path, "Annual_Load.json"))[city][lowercase(buildingtype)]
    end
     # TODO implement BuiltInElectricLoad scaling based on monthly_totals_kwh

    profile_path = joinpath(lib_path, string("Load8760_norm_" * city * "_" * buildingtype * ".dat"))
    normalized_profile = vec(readdlm(profile_path, '\n', Float64, '\n'))

    load = [annual_kwh * ld for ld in normalized_profile]
    return load
end
