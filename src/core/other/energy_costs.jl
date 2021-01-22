
function grid_costs_scenario(m, sys_params, scenario)
	output_vals = Dict()
	grid_costs = 0

	grid_purchases = @variable(m, [scenario.times], lower_bound = 0, base_name = "grid_purchases$(scenario.name)")

	energy_costs = energy_charges(m, grid_purchases, sys_params, scenario)
	grid_costs += energy_costs

	load = []
	#Add wholesale exports
	if sum(abs.(sys_params["electric_tariff"].wholesale_rates)) > 0
		wholesale_export_vals = wholesale_exports(m, sys_params, scenario)
		grid_costs += wholesale_export_vals.costs
		load = wholesale_export_vals.load
	end
	#Add NEM exports
	if sys_params["electric_tariff"].NEM
		 nem_export_vals = nem_exports(m, grid_purchases, sys_params, scenario)
		 grid_costs += nem_export_vals.costs
		 if length(load) == 0
			 load = nem_export_vals.load
		 else
			 load += nem_export_vals.load
		 end
	 end

	if length(sys_params["electric_tariff"].monthly_demand_rates) > 0
        flat_demand_charges = demand_flat_charges(m, grid_purchases, sys_params, scenario)
		grid_costs += flat_demand_charges
    end

    if length(sys_params["electric_tariff"].tou_demand_rates) > 0
		tou_demand_charges = demand_tou_charges(m, grid_purchases, sys_params, scenario)
		grid_costs += tou_demand_charges
	end

	return (gen = grid_purchases, load = load, cost = grid_costs)
end
##

function energy_charges(m, grid_purchases, sys_params, scenario)
	energy_charges_util = @expression(m, (1- sys_params["financial"].owner_tax_pct)*sys_params["financial"].pwf_e * sum([sys_params["electric_tariff"].energy_rates[ts] * grid_purchases[ts] for ts in scenario.times]))
	return energy_charges_util
end
##
function nem_exports(m, grid_purchases, sys_params, scenario)
	nem_exports = @variable(m, [scenario.times], lower_bound = 0, base_name = "nem_exports$(scenario.name)")
	#Cant export more than you purchase
	@constraint(m, sum(nem_exports) <= sum(grid_purchases))

	nem_benefits_util = @expression(m, (1- sys_params["financial"].owner_tax_pct)*sys_params["financial"].pwf_e * sum([sys_params["electric_tariff"].nem_rates[ts] * nem_exports[ts] for ts in scenario.times]))
	return (costs = nem_benefits_util, load = nem_exports)
end
##
function wholesale_exports(m, sys_params, scenario)
	wholesale_exports = @variable(m, [scenario.times], lower_bound = 0, base_name = "wholesale_exports$(scenario.name)")
	#Cant export more than you purchase
	@constraint(m, sum(wholesale_exports) <= sum(sys_params["load"]))

	wholesale_benefits_util = @expression(m, (1- sys_params["financial"].owner_tax_pct)*sys_params["financial"].pwf_e * sum([sys_params["electric_tariff"].wholesale_rates[ts] * wholesale_exports[ts] for ts in scenario.times]))
	return (costs = wholesale_benefits_util, load = nem_exports)

end





function demand_flat_charges(m, grid_purchases, sys_params, scenario)
	month_timesteps = sys_params["electric_tariff"].time_steps_monthly
	months = 1:length(month_timesteps)
	monthly_peak_demand = @variable(m, [months], lower_bound = 0, base_name = "monthly_peak_demand$(scenario.name)")
	@constraint(m, [mth in months, ts in month_timesteps[mth]], monthly_peak_demand[mth] >= grid_purchases[ts])

	demand_flat_charges = @expression(m, (1- sys_params["financial"].owner_tax_pct)*sys_params["financial"].pwf_e * sum( sys_params["electric_tariff"].monthly_demand_rates[mth] * monthly_peak_demand[mth] for mth in months) )
	return demand_flat_charges
end

function demand_tou_charges(m, grid_purchases, sys_params, scenario)
	ratchet_timesteps = sys_params["electric_tariff"].tou_demand_ratchet_timesteps
	ratchets = 1:length(ratchet_timesteps)

	peak_tou_demand = @variable(m, [ratchets], lower_bound = 0, base_name = "demand_tou_charges$(scenario.name)")
	@constraint(m, [r in ratchets, ts in ratchet_timesteps[r]], peak_tou_demand[r] >= grid_purchases[ts])
	demand_tou_charges = @expression(m, (1- sys_params["financial"].owner_tax_pct)*sys_params["financial"].pwf_e * sum( [sys_params["electric_tariff"].tou_demand_rates[r] * peak_tou_demand[r] for r in ratchets]) )
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
