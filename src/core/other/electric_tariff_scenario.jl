function electric_tariff_scenario(m::JuMP.AbstractModel, grid_purchases, scenario::Scenario, params::Dict)
	tariff_return_vals = Dict()
	grid_costs = 0

	energy_costs = energy_charges(m, grid_purchases, params, scenario)
	tariff_return_vals["energyCosts_total"] = energy_costs
	tariff_return_vals["energyCosts_year1"] = energy_costs/params["financial"].pwf_e

	grid_costs += energy_costs

	load = []
	#Add wholesale exports
	if sum(abs.(params["electric_tariff"].wholesale_rates)) > 0
		wholesale_export_vals = wholesale_exports(m, params, scenario)
		tariff_return_vals["wholesaleExportsValue_total"] = -wholesale_export_vals.costs
		tariff_return_vals["wholesaleExportsValue_year_1"] = -wholesale_export_vals.costs/params["financial"].pwf_e
		grid_costs += wholesale_export_vals.costs
		load = wholesale_export_vals.load
	end
	#Add NEM exports
	if params["electric_tariff"].NEM
		 nem_export_vals = nem_exports(m, grid_purchases, params, scenario)
		 tariff_return_vals["nemExportsValue_total"] = -nem_export_vals.costs
		 tariff_return_vals["nemExportsValue_year1"] = -nem_export_vals.costs/params["financial"].pwf_e
		 grid_costs += nem_export_vals.costs
		 if length(load) == 0
			 load = nem_export_vals.load
		 else
			 load += nem_export_vals.load
		 end
	 end

	if length(params["electric_tariff"].monthly_demand_rates) > 0
        flat_demand_charges = demand_flat_charges(m, grid_purchases, params, scenario)
		tariff_return_vals["demandFlatCharges_total"] = flat_demand_charges
		tariff_return_vals["FlatCharges_year1"] = flat_demand_charges/params["financial"].pwf_e

		grid_costs += flat_demand_charges
    end

    if length(params["electric_tariff"].tou_demand_rates) > 0
		tou_demand_charges = demand_tou_charges(m, grid_purchases, params, scenario)
		tariff_return_vals["touDemandCharges_total"] = tou_demand_charges
		tariff_return_vals["touDemandCharges_year1"] = tou_demand_charges/params["financial"].pwf_e
		grid_costs += tou_demand_charges
	end

	add_scenario_results(params["results"], scenario, "electricTariff"; gen = grid_purchases, load = load, other_results = tariff_return_vals)
	if length(load) > 0
		return (load = load, cost = grid_costs)
	else
		return (cost = grid_costs, )
	end
end
##

function energy_charges(m::JuMP.AbstractModel, grid_purchases::AbstractArray, params::Dict, scenario::Scenario)
	energy_charges_util = @expression(m, (1- params["financial"].owner_tax_pct)*params["financial"].pwf_e * sum([params["electric_tariff"].energy_rates[ts] * grid_purchases[ts] for ts in scenario.times]))
	return energy_charges_util
end
##
function nem_exports(m::JuMP.AbstractModel, grid_purchases::AbstractArray, params::Dict, scenario::Scenario)
	nem_exports = @variable(m, [scenario.times], lower_bound = 0, base_name = "nem_exports$(scenario.name)")
	#Cant export more than you purchase
	@constraint(m, sum(nem_exports) <= sum(grid_purchases))

	nem_benefits_util = @expression(m, (1- params["financial"].owner_tax_pct)*params["financial"].pwf_e * sum([params["electric_tariff"].nem_rates[ts] * nem_exports[ts] for ts in scenario.times]))
	return (costs = nem_benefits_util, load = nem_exports)
end
##
function wholesale_exports(m::JuMP.AbstractModel, params::Dict, scenario::Scenario)
	wholesale_exports = @variable(m, [scenario.times], lower_bound = 0, base_name = "wholesale_exports$(scenario.name)")
	#Cant export more than you purchase
	@constraint(m, sum(wholesale_exports) <= sum(params["load"]))

	wholesale_benefits_util = @expression(m, (1- params["financial"].owner_tax_pct)*params["financial"].pwf_e * sum([params["electric_tariff"].wholesale_rates[ts] * wholesale_exports[ts] for ts in scenario.times]))
	return (costs = wholesale_benefits_util, load = nem_exports)

end





function demand_flat_charges(m::JuMP.AbstractModel, grid_purchases::AbstractArray, params::Dict, scenario::Scenario)
	month_timesteps = params["electric_tariff"].time_steps_monthly
	months = 1:length(month_timesteps)
	monthly_peak_demand = @variable(m, [months], lower_bound = 0, base_name = "monthly_peak_demand$(scenario.name)")
	@constraint(m, [mth in months, ts in month_timesteps[mth]], monthly_peak_demand[mth] >= grid_purchases[ts])

	demand_flat_charges = @expression(m, (1- params["financial"].owner_tax_pct)*params["financial"].pwf_e * sum( params["electric_tariff"].monthly_demand_rates[mth] * monthly_peak_demand[mth] for mth in months) )
	return demand_flat_charges
end

function demand_tou_charges(m::JuMP.AbstractModel, grid_purchases::AbstractArray, params::Dict, scenario::Scenario)
	ratchet_timesteps = params["electric_tariff"].tou_demand_ratchet_timesteps
	ratchets = 1:length(ratchet_timesteps)

	peak_tou_demand = @variable(m, [ratchets], lower_bound = 0, base_name = "demand_tou_charges$(scenario.name)")
	@constraint(m, [r in ratchets, ts in ratchet_timesteps[r]], peak_tou_demand[r] >= grid_purchases[ts])
	demand_tou_charges = @expression(m, (1- params["financial"].owner_tax_pct)*params["financial"].pwf_e * sum( [params["electric_tariff"].tou_demand_rates[r] * peak_tou_demand[r] for r in ratchets]) )
	return demand_tou_charges
end
# 	    # NOTE: levelization_factor is baked into dvNEMexport, dvWHLexport
# 	    @expression(m, TotalExportBenefit, p.pwf_e * p.hours_per_timestep * sum(
# 	        sum( p.etariff.export_rates[u][ts] * m[:dvStorageExport][b,u,ts] for b in p.storage.can_grid_charge, u in p.storage.export_bins)
# 	      + sum( p.etariff.export_rates[:NEM][ts] * m[:dvNEMexport][t, ts] for t in p.techs)
# 	      + sum( p.etariff.export_rates[:WHL][ts] * m[:dvWHLexport][t, ts]  for t in p.techs)
# 	        for ts in p.time_steps )
# 	    )
# 	    @expression(m, ExportBenefitYr1, TotalExportBenefit / p.pwf_e)
# 	else
# 	    @expression(m, TotalExportBenefit, 0)
# 	    @expression(m, ExportBenefitYr1, 0)
# 	end
# end
# #
