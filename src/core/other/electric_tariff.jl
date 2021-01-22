import Dates: daysinmonth, Date
# using JuMP
# using Dates
# using GLPK
# using Parameters
# using JuMP.Containers: DenseAxisArray
# import JSON
# import HTTP
"""
data for electric tariff in reopt model
    can be defined using custom rates or URDB rate
"""
@with_kw struct ElectricTariff
    energy_rates::Array{Float64,1}

    monthly_demand_rates::Array{Float64,1}
    time_steps_monthly::Array{Array{Int64,1},1}  # length = 0 or 12

    tou_demand_rates::Array{Float64,1}
    tou_demand_ratchet_timesteps::Array{Array{Int64,1},1}  # length = n_tou_demand_ratchets

    fixed_monthly_charge::Float64
    annual_min_charge::Float64
    min_monthly_charge::Float64
    NEM::Bool
    nem_rates::Array{Float64, 1}
    wholesale_rates::Array{Float64, 1}
end
##

function tariff_system(input_dic)
    return initialize_with_inputs(input_dic, ElectricTariff, "ElectricTariff", setup_electricity_tariff_inputs)
end
##

function setup_electricity_tariff_inputs(value_dic, input_dic)
    u = nothing
    #TODO update time_steps_per_hour to allow for more than hourly data
    time_steps_per_hour = 1
    year = value_dic["year"]

    if haskey(value_dic, "urdb_label")
        u = URDBrate(value_dic["urdb_label"], year, time_steps_per_hour = time_steps_per_hour)

    elseif haskey(value_dic, "urdb_response")
        u = URDBrate(value_dic["urdb_response"], year, time_steps_per_hour=time_steps_per_hour)

    elseif haskey(value_dic, "monthly_energy_rates")
        invalid_args = String[]
        monthly_energy_rates = value_dic["monthly_energy_rates"]
        if !(length(monthly_energy_rates) == 12)
            push!(invalid_args, "length(monthly_energy_rates) must equal 12, got length $(length(monthly_energy_rates))")
        end

        if haskey(value_dic, "monthly_demand_rates")
            monthly_demand_rates = value_dic["monthly_demand_rates"]
            demand_rates_monthly = monthly_demand_rates
            if !(length(value_dic["monthly_demand_rates"]) == 12)
                push!(invalid_args, "length(monthly_demand_rates) must equal 12, got length $(length(monthly_demand_rates))")
            end
        else
            monthly_demand_rates = Float64[]
        end

        if length(invalid_args) > 0
            error("Invalid argument values: $(invalid_args)")
        end

        tou_demand_rates = Float64[]
        tou_demand_ratchet_timesteps = []
        time_steps_monthly = get_monthly_timesteps(year, time_steps_per_hour=time_steps_per_hour)
        energy_rates = Real[]
        for m in 1:12
            append!(energy_rates, [monthly_energy_rates[m] for ts in time_steps_monthly[m]])
        end

        fixed_monthly_charge = 0.0
        annual_min_charge = 0.0
        min_monthly_charge = 0.0

        if value_dic["NEM"]
            nem_rates = [-0.999 * x for x in energy_rates]
        else
            nem_rates = [0 for _ in 1:12]
        end
    else
        error("Creating ElectricTariff requires at least urdb_label or monthly rates.")
    end

    if !isnothing(u)

        if value_dic["NEM"]
            t = get_tier_with_lowest_energy_rate(u)
            nem_rates = [-0.999 * x for x in u.energy_rates[t,:]]
        else
            nem_rates = [0 for _ in 1:12]
        end

        energy_rates, monthly_demand_rates, tou_demand_rates = remove_tiers_from_urdb_rate(u)
        time_steps_monthly = Array[]
        if !isempty(u.monthly_demand_rates)
            time_steps_monthly =
                get_monthly_timesteps(year, time_steps_per_hour=time_steps_per_hour)
        end

        tou_demand_ratchet_timesteps = u.tou_demand_ratchet_timesteps
        fixed_monthly_charge = u.fixed_monthly_charge
        annual_min_charge = u.annual_min_charge
        min_monthly_charge = u.min_monthly_charge
    end

    #= export_rates
    3 "tiers": 1. NEM (Net Energy Metering), 2. WHL (Wholesale), 3. CUR (Curtail)
    - if NEM then set ExportRate[:Nem, :] to energy_rate[tier_with_lowest_energy_rate, :]
        - otherwise set to 100 dollars/kWh
    - user can provide either scalar wholesale rate or vector of timesteps,
        - otherwise set to 100 dollars/kWh
    - curtail cost set to zero by default, but can be specified same as wholesale rate
    =#

    wholesale_rates = create_export_rate(value_dic["wholesale_rate"], length(energy_rates), time_steps_per_hour)

    curtail_costs = create_export_rate(value_dic["curtail_cost"], length(energy_rates), time_steps_per_hour)

    value_dic["energy_rates"] = energy_rates
    value_dic["monthly_demand_rates"] = monthly_demand_rates
    value_dic["time_steps_monthly"] = time_steps_monthly
    value_dic["tou_demand_rates"] = tou_demand_rates
    value_dic["tou_demand_ratchet_timesteps"] = tou_demand_ratchet_timesteps
    value_dic["fixed_monthly_charge"] = fixed_monthly_charge
    value_dic["annual_min_charge"] = annual_min_charge
    value_dic["min_monthly_charge"] = min_monthly_charge
    value_dic["nem_rates"] = nem_rates
    value_dic["wholesale_rates"] = wholesale_rates
    return value_dic
end
##

# input_values = Dict("ElectricTariff"=>Dict("urdb_label" => "5ed6c1a15457a3367add15ae", "curtail_cost"=>0))
# x = initialize_with_inputs(input_values, ElectricTariff, "ElectricTariff", setup_electricity_tariff_inputs)

abstract type REoptData end
# https://discourse.julialang.org/t/vector-of-matrices-vs-multidimensional-arrays/9602/5
# 5d2360465457a3f77ddc131e has TOU demand
# 59bc22705457a3372642da67 has monthly tiered demand (no TOU demand)

"""
    Base.@kwdef struct URDBrate <: REoptData

Contains some of the data for ElectricTariff
"""
struct URDBrate <: REoptData
    year::Int
    time_steps_per_hour::Int

    energy_rates::Array{Float64,2}  # tier X time
    energy_tier_limits::Array{Real,1}

    n_monthly_demand_tiers::Int
    monthly_demand_tier_limits::Array{Real,1}
    monthly_demand_rates::Array{Float64,2}  # month X tier TODO change tier locations in reopt.jl to be consistent

    n_tou_demand_tiers::Int
    tou_demand_tier_limits::Array{Real,1}
    tou_demand_rates::Array{Float64,2}  # ratchet X tier
    tou_demand_ratchet_timesteps::Array{Array{Int64,1},1}  # length = n_tou_demand_ratchets

    fixed_monthly_charge::Float64
    annual_min_charge::Float64
    min_monthly_charge::Float64
end


function get_tier_with_lowest_energy_rate(u::URDBrate)
    """
    ExportRate should be lowest energy cost for tiered rates.
    Otherwise, ExportRate can be > FuelRate, which leads REopt to export all PV energy produced.
    """
    tier_with_lowest_energy_cost = 1
    if length(u.energy_tier_limits) > 1
        annual_energy_charge_sums = Float64[]
        for etier in u.energy_rates
            push!(annual_energy_charge_sums, sum(etier))
        end
        tier_with_lowest_energy_cost =
            findall(annual_energy_charge_sums .== minimum(annual_energy_charge_sums))[1]
    end
    return tier_with_lowest_energy_cost
end

# TODO: dispatch custom rates based on options: TOU, monthly, etc.
function CustomRate(flat_energy::Real, flat_demand::Real=0) end


"""
    function create_export_rate(e::Nothing, N::Int, ts_per_hour::Int=1)
No export rate provided by user: set to 100 dollars/kWh for all time
"""
function create_export_rate(e::Nothing, N::Int, ts_per_hour::Int=1)
    [100 for _ in range(1, stop=N) for ts in 1:ts_per_hour]
end


"""
    function create_export_rate(e::T, N::Int, ts_per_hour::Int=1) where T<:Real
Case for scaler export rate provided -> convert to array of timesteps
"""
function create_export_rate(e::T, N::Int, ts_per_hour::Int=1) where T<:Real
    [float(-1*e) for ts in range(1, stop=N) for ts_per_hour::Int=1]
end


"""
    function create_export_rate(e::Array{<:Real, 1}, N::Int, ts_per_hour::Int=1)

Check length of e and upsample if length(e) != N
"""
function create_export_rate(e::Array{<:Real, 1}, N::Int, ts_per_hour::Int=1)
    Ne = length(e)
    if Ne != Int(N/ts_per_hour) || Ne != N
        @error "Export rates do not have correct number of entries. Must be $(N) or $(Int(N/ts_per_hour))."
    end
    if Ne != N  # upsample
        export_rates = [-1*x for x in e for ts in 1:ts_per_hour]
    else
        export_rates = -1*e
    end
    return export_rates
end


"""
    get_monthly_timesteps(year::Int; time_steps_per_hour=1)

return Array{Array{Int64,1},1}, size = (12,)
"""
function get_monthly_timesteps(year::Int; time_steps_per_hour=1)
    a = Array[]
    i = 1
    for m in range(1, stop=12)
        n_days = daysinmonth(Date(string(year) * "-" * string(m)))
        stop = n_days * 24 * time_steps_per_hour + i - 1
        steps = [step for step in range(i, stop=stop)]
        append!(a, [steps])
        i = stop + 1
    end
    return a
end

# TODO use this function only for URDBrate
function remove_tiers_from_urdb_rate(u::URDBrate)
    # tariff args: have to validate that there are no tiers
    if length(u.energy_tier_limits) > 1
        @warn "Energy rate contains tiers. Using the first tier!"
    end
    elec_rates = vec(u.energy_rates[1,:])

    if u.n_monthly_demand_tiers > 1
        @warn "Monthly demand rate contains tiers. Using the last tier!"
    end
    if u.n_monthly_demand_tiers > 0
        demand_rates_monthly = vec(u.monthly_demand_rates[:,u.n_monthly_demand_tiers])
    else
        demand_rates_monthly = vec(u.monthly_demand_rates)  # 0×0 Array{Float64,2}
    end

    if u.n_tou_demand_tiers > 1
        @warn "TOU demand rate contains tiers. Using the last tier!"
    end
    if u.n_tou_demand_tiers > 0
        demand_rates = vec(u.tou_demand_rates[:,u.n_tou_demand_tiers])
    else
        demand_rates = vec(u.tou_demand_rates)
    end

    return elec_rates, demand_rates_monthly, demand_rates
end

##

"""
    URDBrate(urdb_label::String, year::Int)

download URDB dict, parse into reopt inputs, return ElectricTariff struct.
    year is required to align weekday/weekend schedules.
"""
function URDBrate(urdb_label::String, year::Int=2019; time_steps_per_hour=1)
    rate = download_urdb(urdb_label)
    demand_min = get(rate, "peakkwcapacitymin", 0.0)  # TODO add check for site min demand against tariff?

    n_monthly_demand_tiers, monthly_demand_tier_limits, monthly_demand_rates,
      n_tou_demand_tiers, tou_demand_tier_limits, tou_demand_rates, tou_demand_ratchet_timesteps =
      parse_demand_rates(rate, year)

    energy_rates, energy_tier_limits = parse_urdb_energy_costs(rate, year)

    fixed_monthly_charge, annual_min_charge, min_monthly_charge = parse_urdb_fixed_charges(rate)

    URDBrate(
        year,
        time_steps_per_hour,

        energy_rates,
        energy_tier_limits,

        n_monthly_demand_tiers,
        monthly_demand_tier_limits,
        monthly_demand_rates,

        n_tou_demand_tiers,
        tou_demand_tier_limits,
        tou_demand_rates,
        tou_demand_ratchet_timesteps,

        fixed_monthly_charge,
        annual_min_charge,
        min_monthly_charge,
    )
end


"""
    URDBrate(urdb_response::Dict, year::Int)

process URDB dict, parse into reopt inputs, return ElectricTariff struct.
    year is required to align weekday/weekend schedules.
"""
function URDBrate(urdb_response::Dict, year::Int=2019; time_steps_per_hour=1)

    demand_min = get(urdb_response, "peakkwcapacitymin", 0.0)  # TODO add check for site min demand against tariff?

    n_monthly_demand_tiers, monthly_demand_tier_limits, monthly_demand_rates,
      n_tou_demand_tiers, tou_demand_tier_limits, tou_demand_rates, tou_demand_ratchet_timesteps =
      parse_demand_rates(urdb_response, year)

    energy_rates, energy_tier_limits = parse_urdb_energy_costs(urdb_response, year)

    fixed_monthly_charge, annual_min_charge, min_monthly_charge = parse_urdb_fixed_charges(urdb_response)

    URDBrate(
        year,
        time_steps_per_hour,

        energy_rates,
        energy_tier_limits,

        n_monthly_demand_tiers,
        monthly_demand_tier_limits,
        monthly_demand_rates,

        n_tou_demand_tiers,
        tou_demand_tier_limits,
        tou_demand_rates,
        tou_demand_ratchet_timesteps,

        fixed_monthly_charge,
        annual_min_charge,
        min_monthly_charge,
    )
end


function download_urdb(urdb_label::String; version::Int=7)
    url = string("https://api.openei.org/utility_rates", "?api_key=", urdb_key,
                "&version=", version , "&format=json", "&detail=full",
                "&getpage=", urdb_label
    )
    response = nothing
    try
        @info "Checking URDB for " urdb_label
        r = HTTP.get(url, require_ssl_verification=false)  # cannot verify on NREL VPN
        response = JSON.parse(String(r.body))
        if r.status != 200
            error("Bad response from URDB: $(response["errors"])")  # TODO URDB has "errors"?
        end
    catch e
        error("Error occurred :$(e)")
    end

    rates = response["items"]  # response['items'] contains a vector of dicts
    if length(rates) == 0
        error("Could not find $(urdb_label) in URDB.")
    end
    if rates[1]["label"] == urdb_label
        return rates[1]
    else
        error("Could not find $(urdb_label) in URDB.")
    end
end


"""
    parse_urdb_energy_costs(d::Dict, year::Int; time_steps_per_hour=1, bigM = 1.0e8)

use URDB dict to return rates, energy_cost_vector, energy_tier_limits_kwh where:
    - rates is vector summary of rates within URDB (used for average rates when necessary)
    - energy_cost_vector is a vector of vectors with inner vectors for each energy rate tier,
        inner vectors are costs in each time step
    - energy_tier_limits_kwh is a vector of upper kWh limits for each energy tier
"""
function parse_urdb_energy_costs(d::Dict, year::Int; time_steps_per_hour=1, bigM = 1.0e8)
    if length(d["energyratestructure"]) == 0
        error("No energyratestructure in URDB response.")
    end
    # TODO check bigM (in multiple functions)
    energy_tiers = Float64[]
    for energy_rate in d["energyratestructure"]
        append!(energy_tiers, length(energy_rate))
    end
    energy_tier_set = Set(energy_tiers)
    if length(energy_tier_set) > 1
        @warn "energy periods contain different numbers of tiers, using limits of period with most tiers"
    end
    period_with_max_tiers = findall(energy_tiers .== maximum(energy_tiers))[1]
    n_energy_tiers = Int(maximum(energy_tier_set))

    rates = Float64[]
    energy_tier_limits_kwh = Float64[]
    non_kwh_units = false

    for energy_tier in d["energyratestructure"][period_with_max_tiers]
        # energy_tier is a dictionary, eg. {'max': 1000, 'rate': 0.07531, 'adj': 0.0119, 'unit': 'kWh'}
        energy_tier_max = get(energy_tier, "max", bigM)

        if "rate" in keys(energy_tier) || "adj" in keys(energy_tier)
            append!(energy_tier_limits_kwh, energy_tier_max)
        end

        if "unit" in keys(energy_tier)
            if string(energy_tier["unit"]) != "kWh"
                @warn "Using average rate in tier due to exotic units of " energy_tier["unit"]
                non_kwh_units = true
            end
        end

        append!(rates, get(energy_tier, "rate", 0) + get(energy_tier, "adj", 0))
    end

    if non_kwh_units
        rate_average = sum(rates) / maximum([length(rates), 1])
        n_energy_tiers = 1
        energy_tier_limits_kwh = Float64[bigM]
    end

    energy_cost_vector = Float64[]

    for tier in range(1, stop=n_energy_tiers)

        for month in range(1, stop=12)
            n_days = daysinmonth(Date(string(year) * "-" * string(month)))

            for day in range(1, stop=n_days)

                for hour in range(1, stop=24)

                    # NOTE: periods are zero indexed
                    if dayofweek(Date(year, month, day)) < 6  # Monday == 1
                        period = d["energyweekdayschedule"][month][hour] + 1
                    else
                        period = d["energyweekendschedule"][month][hour] + 1
                    end
                    # workaround for cases where there are different numbers of tiers in periods
                    n_tiers_in_period = length(d["energyratestructure"][period])
                    if n_tiers_in_period == 1
                        tier_use = 1
                    elseif tier > n_tiers_in_period
                        tier_use = n_tiers_in_period
                    else
                        tier_use = tier
                    end
                    if non_kwh_units
                        rate = rate_average
                    else
                        rate = get(d["energyratestructure"][period][tier_use], "rate", 0)
                    end
                    total_rate = rate + get(d["energyratestructure"][period][tier_use], "adj", 0)

                    for step in range(1, stop=time_steps_per_hour)  # repeat hourly rates intrahour
                        append!(energy_cost_vector, round(total_rate, digits=6))
                    end
                end
            end
        end
    end
    energy_rates = reshape(energy_cost_vector, (n_energy_tiers, :))
    return energy_rates, energy_tier_limits_kwh
end


"""
    parse_demand_rates(d::Dict, year::Int; bigM=1.0e8)

Parse monthly ("flat") and TOU demand rates
    can modify URDB dict when there is inconsistent numbers of tiers in rate structures
"""
function parse_demand_rates(d::Dict, year::Int; bigM=1.0e8)

    if haskey(d, "flatdemandstructure")
        scrub_urdb_demand_tiers!(d["flatdemandstructure"])
        monthly_demand_tier_limits = parse_urdb_demand_tiers(d["flatdemandstructure"])
        n_monthly_demand_tiers = length(monthly_demand_tier_limits)
        monthly_demand_rates = parse_urdb_monthly_demand(d, n_monthly_demand_tiers)
    else
        monthly_demand_tier_limits = []
        n_monthly_demand_tiers = 0
        monthly_demand_rates = Array{Float64,2}(undef, 0, 0)
    end

    if haskey(d, "demandratestructure")
        scrub_urdb_demand_tiers!(d["demandratestructure"])
        tou_demand_tier_limits = parse_urdb_demand_tiers(d["demandratestructure"])
        n_tou_demand_tiers = length(tou_demand_tier_limits)
        ratchet_timesteps, tou_demand_rates = parse_urdb_tou_demand(d, year=year, n_tiers=n_tou_demand_tiers)
    else
        tou_demand_tier_limits = []
        n_tou_demand_tiers = 0
        ratchet_timesteps = []
        tou_demand_rates = Array{Float64,2}(undef, 0, 0)
    end

    return n_monthly_demand_tiers, monthly_demand_tier_limits, monthly_demand_rates,
           n_tou_demand_tiers, tou_demand_tier_limits, tou_demand_rates, ratchet_timesteps

end


"""
    scrub_urdb_demand_tiers!(A::Array)

validate flatdemandstructure and demandratestructure have equal number of tiers across periods
"""
function scrub_urdb_demand_tiers!(A::Array)
    if length(A) == 0
        return
    end
    len_tiers = Int[length(r) for r in A]
    len_tiers_set = Set(len_tiers)
    n_tiers = maximum(len_tiers_set)

    if length(len_tiers_set) > 1
        @warn """Demand rate structure has varying number of tiers in periods.
                 Making the number of tiers the same across all periods by repeating the last tier."""
        for (i, rate) in enumerate(A)
            n_tiers_in_period = length(rate)
            if n_tiers_in_period != n_tiers
                rate_new = rate
                last_tier = rate[n_tiers_in_period]
                for j in range(1, stop=n_tiers - n_tiers_in_period)
                    append!(rate_new, last_tier)
                end
                A[i] = rate_new
            end
        end
    end
end


"""
    parse_urdb_demand_tiers(A::Array; bigM=1.0e8)

set up and validate demand tiers
    returns demand_tiers::Array{Float64, n_tiers}
"""
function parse_urdb_demand_tiers(A::Array; bigM=1.0e8)
    if length(A) == 0
        return []
    end
    len_tiers = Int[length(r) for r in A]
    n_tiers = maximum(len_tiers)
    period_with_max_tiers = findall(len_tiers .== maximum(len_tiers))[1]

    # set up tiers and validate that the highest tier has the same value across periods
    demand_tiers = Dict()
    demand_maxes = Float64[]
    for period in range(1, stop=length(A))
        demand_max = Float64[]
        for tier in A[period]
            append!(demand_max, get(tier, "max", bigM))
        end
        demand_tiers[period] = demand_max
        append!(demand_maxes, demand_max[end])  # TODO should this be maximum(demand_max)?
    end

    # test if the highest tier is the same across all periods
    if length(Set(demand_maxes)) > 1
        @warn "Highest demand tiers do not match across periods: using max tier from largest set of tiers."
    end
    return demand_tiers[period_with_max_tiers]
end


"""
    parse_urdb_monthly_demand(d::Dict)

return monthly demand rates as array{month, tier}
"""
function parse_urdb_monthly_demand(d::Dict, n_tiers)
    if !haskey(d, "flatdemandmonths")
        return []
    end
    if length(d["flatdemandmonths"]) == 0
        return []
    end

    demand_rates = zeros(12, n_tiers)  # array(month, tier)
    for month in range(1, stop=12)
        period = d["flatdemandmonths"][month] + 1  # URDB uses zero-indexing
        rates = d["flatdemandstructure"][period]  # vector of dicts

        for (t, tier) in enumerate(rates)
            demand_rates[month, t] = round(get(tier, "rate", 0.0) + get(tier, "adj", 0.0), digits=6)
        end
    end
    return demand_rates
end


"""
    parse_urdb_tou_demand(d::Dict; year::Int, n_tiers::Int)

return array of arrary for ratchet time steps, tou demand rates array{ratchet, tier}
"""
function parse_urdb_tou_demand(d::Dict; year::Int, n_tiers::Int)
    if !haskey(d, "demandratestructure")
        return [], []
    end
    n_periods = length(d["demandratestructure"])
    ratchet_timesteps = Array[]
    rates_vec = Float64[]  # array(ratchet_num, tier), reshape later
    n_ratchets = 0  # counter

    for month in range(1, stop=12)
        for period in range(0, stop=n_periods)
            time_steps = get_tou_demand_steps(d, year=year, month=month, period=period-1)
            if length(time_steps) > 0  # can be zero! not every month contains same number of periods
                n_ratchets += 1
                append!(ratchet_timesteps, [time_steps])
                for (t, tier) in enumerate(d["demandratestructure"][period])
                    append!(rates_vec, round(get(tier, "rate", 0.0) + get(tier, "adj", 0.0), digits=6))
                end
            end
        end
    end
    rates = reshape(rates_vec, (:, n_tiers))  # Array{Float64,2}
    ratchet_timesteps = convert(Array{Array{Int64,1},1}, ratchet_timesteps)
    return ratchet_timesteps, rates
end


"""
    get_tou_demand_steps(d::Dict; year::Int, month::Int, period::Int, time_steps_per_hour=1)

return Array{Int, 1} for timesteps in ratchet (aka period)
"""
function get_tou_demand_steps(d::Dict; year::Int, month::Int, period::Int, time_steps_per_hour=1)
    step_array = Int[]
    start_step = 1
    start_hour = 1

    if month > 1
        plus_days = 0
        for m in range(1, stop=month-1)
            plus_days += daysinmonth(Date(string(year) * "-" * string(m)))
        end
        start_hour += plus_days * 24
        start_step = start_hour * time_steps_per_hour
    end

    hour_of_year = start_hour
    step_of_year = start_step

    for day in range(1, stop=daysinmonth(Date(string(year) * "-" * string(month))))
        for hour in range(1, stop=24)
            if dayofweek(Date(year, month, day)) < 6 &&
               d["demandweekdayschedule"][month][hour] == period
                append!(step_array, step_of_year)
            elseif dayofweek(Date(year, month, day)) > 5 &&
               d["demandweekendschedule"][month][hour] == period
                append!(step_array, step_of_year)
            end
            step_of_year += 1
        end
        hour_of_year += 1
    end
    return step_array
end


"""
    parse_urdb_fixed_charges(d::Dict)

return fixed_monthly, annual_min, min_monthly :: Float64
"""
function parse_urdb_fixed_charges(d::Dict)
    fixed_monthly = Float64(get(d, "fixedmonthlycharge", 0.0))
    annual_min = Float64(get(d, "annualmincharge", 0.0))
    min_monthly = Float64(get(d, "minmonthlycharge", 0.0))
    return fixed_monthly, annual_min, min_monthly
end
