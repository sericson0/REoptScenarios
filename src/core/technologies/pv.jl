@with_kw mutable struct PV
      tilt::Float64
      array_type::Int64
      module_type::Int64
      losses::Float64
      azimuth::Float64
      location::String
      min_kw::Float64
      max_kw::Float64
      cost_per_kw::Float64
      om_cost_per_kw::Float64
      degradation_pct::Float64
      macrs_option_years::Int64
      macrs_bonus_pct::Float64
      macrs_itc_reduction::Float64
      total_itc_pct::Float64
      total_rebate_per_kw::Float64
      kw_per_square_foot::Float64
      acres_per_kw::Float64
      inv_eff::Float64
      dc_ac_ratio::Float64
      production_factor::Array{Float64,1}
      degradation_factor::Float64
end

##
function setup_pv_inputs(value_dic::Dict, params::Dict)
	financial = params["financial"]
	site = params["site"]

	if !(haskey(value_dic, "tilt"))
		value_dic["tilt"] = site.latitude
	end
	#Calculates maximum system size
	roof_max_kw = site.roof_squarefeet * value_dic["kw_per_square_foot"]
	land_max_kw = site.land_acres / value_dic["acres_per_kw"]
	if value_dic["location"] == "both"
		value_dic["max_kw"] = min(value_dic["max_kw"], roof_max_kw + land_max_kw)
	elseif value_dic["location"] == "roof"
		value_dic["max_kw"] = min(value_dic["max_kw"], roof_max_kw)
	else
		value_dic["max_kw"] = min(value_dic["max_kw"], land_max_kw)
	end
	#Gets production factor from PV Watts
	if !(haskey(value_dic, "production_factor"))
		value_dic["production_factor"] = prodfactor(value_dic, site.longitude, site.latitude)
	end

	value_dic["degradation_factor"] = levelization_factor(financial.analysis_years, financial.elec_cost_escalation_pct, financial.offtaker_discount_pct, value_dic["degradation_pct"])

	return value_dic
end
##
function pv_system(m::JuMP.AbstractModel, pv::PV, params::Dict)
	@variable(m, pv.min_kw <= dv_pv_kw <= pv.max_kw)

	cost = pv_cost(m, pv, params["financial"])

	params["results"]["system"]["pv_kw"] = m[:dv_pv_kw]
	params["results"]["system"]["pv_capital_cost"] = cost
	return cost
end
##
function pv_scenario(m::JuMP.AbstractModel, params::Dict, scenario::Scenario, production_factor::Array{Float64,1})
    production_factor *= scenario.pv_prod_factor_scaling * params["pv"].degradation_factor
    pv_output = @variable(m, [scenario.times], base_name = "dv_pv_output$(scenario.name)", lower_bound = 0)
    #Cannot output more than pv production factor. Could make hard constraint if do not allow turndown
    @constraint(m, [ts in scenario.times], pv_output[ts] <= production_factor[ts] * m[:dv_pv_kw])

	add_scenario_results(params["results"], scenario, "pv"; gen = pv_output)
    return (gen = pv_output, cost = 0)
end
##
function pv_cost(m::JuMP.AbstractModel, pv::PV, financial::Financial)
    effective_cost_per_kw = effective_cost(;
                itc_basis= pv.cost_per_kw,
                replacement_cost= 0.0,
                replacement_year= financial.analysis_years,
                discount_rate= financial.owner_discount_pct,
                tax_rate= financial.owner_tax_pct,
                itc= pv.total_itc_pct,
                macrs_schedule = pv.macrs_option_years == 7 ? financial.macrs_seven_year : financial.macrs_five_year,
                macrs_bonus_pct= pv.macrs_bonus_pct,
                macrs_itc_reduction = pv.macrs_itc_reduction,
                rebate_per_kw = pv.total_rebate_per_kw
            )
    capital_costs = effective_cost_per_kw * m[:dv_pv_kw]
    om_costs = financial.pwf_om * pv.om_cost_per_kw * m[:dv_pv_kw] * (1-financial.owner_tax_pct)
    return financial.two_party_factor * (capital_costs + om_costs)
end
##
function validate_pv_args(pv::PV)
  invalid_args = String[]
  if !(0 <= pv.azimuth < 360)
      push!(invalid_args, "azimuth must satisfy 0 <= azimuth < 360, got $(azimuth)")
  end
  if !(pv.array_type in [0, 1, 2, 3, 4])
      push!(invalid_args, "array_type must be in [0, 1, 2, 3, 4], got $(array_type)")
  end
  if !(pv.module_type in [0, 1, 2])
      push!(invalid_args, "module_type must be in [0, 1, 2], got $(module_type)")
  end
  if !(0.0 <= pv.losses <= 0.99)
      push!(invalid_args, "losses must satisfy 0.0 <= losses <= 0.99, got $(losses)")
  end
  if !(0 <= pv.tilt <= 90)
      push!(invalid_args, "tilt must satisfy 0 <= tilt <= 90, got $(tilt)")
  end
  if !(pv.location in ["roof", "ground", "both"])
      push!(invalid_args, "location must be in [\"roof\", \"ground\", \"both\"], got $(location)")
  end
  if !(0.0 <= pv.degradation_pct <= 1.0)
      push!(invalid_args, "degradation_pct must satisfy 0 <= degradation_pct <= 1, got $(degradation_pct)")
  end
  if !(0.0 <= pv.inv_eff <= 1.0)
      push!(invalid_args, "inv_eff must satisfy 0 <= inv_eff <= 1, got $(inv_eff)")
  end
  if !(0.0 <= pv.dc_ac_ratio <= 2.0)
      push!(invalid_args, "dc_ac_ratio must satisfy 0 <= dc_ac_ratio <= 1, got $(dc_ac_ratio)")
  end
  # TODO validate additional args
  if length(invalid_args) > 0
      error("Invalid argument values: $(invalid_args)")
  end
end
##
function pv_args_grid_scenario(m::JuMP.AbstractModel, scenario::GridScenario, params::Dict)
	production_factor = scenario.pv_prod_factor
	if production_factor == nothing
		production_factor = params["pv"].production_factor
	end
	return production_factor
end
##

function pv_args_outage_event(m::JuMP.AbstractModel, event::OutageEvent, params::Dict, outage_start::Int)
	production_factor = event.pv_prod_factor
	if production_factor == nothing
		production_factor = params["pv"].production_factor
	end
	return production_factor
end
##
#Get pv watts data
function prodfactor(vals::Dict, longitude::Float64, latitude::Float64)
    timeframe = "hourly"
    url = string("https://developer.nrel.gov/api/pvwatts/v6.json", "?api_key=", nrel_developer_key,
        "&lat=", latitude , "&lon=", longitude, "&tilt=", vals["tilt"],
        "&system_capacity=1", "&azimuth=", vals["azimuth"], "&module_type=", vals["module_type"],
        "&array_type=", vals["array_type"], "&losses=", round(vals["losses"]*100, digits=3), "&dc_ac_ratio=", vals["dc_ac_ratio"],
        "&gcr=", 0.4, "&inv_eff=", vals["inv_eff"]*100, "&timeframe=", timeframe, "&dataset=nsrdb",
        "&radius=", 100
    )

    try
        @info "Querying PVWatts for prodfactor"
        r = HTTP.get(url)
        response = JSON.parse(String(r.body))
        if r.status != 200
            error("Bad response from PVWatts: $(response["errors"])")
            # julia does not get here even with status != 200 b/c it jumps ahead to CIDER/reopt/src/core/reopt_inputs.jl:114
            # and raises ArgumentError: indexed assignment with a single value to many locations is not supported; perhaps use broadcasting `.=` instead?
        end
        @info "PVWatts success."
        watts = get(response["outputs"], "ac", []) / 1000  # scale to 1 kW system (* 1 kW / 1000 W)

        return watts
    catch e
        return "Error occurred : $e"
    end
end
