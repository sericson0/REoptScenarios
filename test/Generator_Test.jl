using JuMP
# using GLPK
using Gurobi
#Ran tests using Gurobi. Pick your favorite optimizer and have fun
Optimizer_Type = Gurobi.Optimizer

import JSON

# import CSV
cd(joinpath(dirname(dirname(@__FILE__)), "src"))
Pkg.activate(".")
include("../src/REoptScenarios.jl")
using .REoptScenarios

#______________________________________________________________________________________
#Simple tariff and only Generator
m = Model(Optimizer_Type)
params = initialize_system(m, "../test/Inputs/Gen_Test.json")
grid_scenario_vals = initialize_grid_scenarios(m, "../test/Inputs/Gen_test.json", params)
@objective(m, Min, params["system_cost"] + grid_scenario_vals.costs)
optimize!(m)

println("Optimized. Objective value is ", round(objective_value(m); digits=  2), ". should be 31")
println("Generator size is: ", round(value(m[:dv_generator_kw]); digits = 2), ". Should be 8")
vars = all_variables(m)
var_names = name.(vars)
M = Dict(zip(var_names, value.(vars)))

for v in sort(var_names)
    println(v, ": ", M[v])
end
#______________________________________________________________________________________
#Complex tariff (demand charges and tou demand rates), and PV + storage
m = Model(Optimizer_Type)
params = initialize_system(m, "../test/Inputs/pv_storage.json")
grid_scenario_vals = initialize_grid_scenarios(m, "../test/Inputs/pv_storage.json", params)
@objective(m, Min, params["system_cost"] + grid_scenario_vals.costs)
# @objective(m, Min, params["system_cost"] + grid_scenario_vals.costs + outage_scenario_vals)
optimize!(m)
println("LCC is: ",  round(objective_value(m); digits = 0), " Value should be 1.2388763e7")

println("PV: ", round(value(m[:dv_pv_kw]); digits = 2), ". Value should be Should be 216.67")
println("Storage kw: ", round(value(m[:dv_storage_kw]); digits = 2), ". Value should be 55.88")
println("Storage kWh: ", round(value(m[:dv_storage_kwh]); digits = 2), ". Value should be 78.91")
#______________________________________________________________________________________
#Tests the multiple scenarios approach
#Single year with no incentives or taxes.
#Uses "PV", but with production factor set to 1.
#PV cost is 2.75, and energy cost is 1.
#base load is [5, 5, 10, 11, 11].
#With single scenario optimal PV is 10 and lcc is 2.75*10 + 2*1 = 29.5
m = Model(Optimizer_Type)
params = initialize_system(m, "../test/Inputs/Gen_Test.json")
grid_scenario_vals = initialize_grid_scenarios(m, "../test/Inputs/Multiple_Scenarios_Test.json", params)
@objective(m, Min, params["system_cost"] + grid_scenario_vals.costs)
optimize!(m)
println("System cost is $(objective_value(m))", ". Should be 29.5")
println("PV value is: ", value(m[:dv_pv_kw]), ". Should be 10")

#
#Now we are going run with two scenarios, one where the load is 30% smaller and one where load is 30% larger.
#Load is now [3.5, 3.5, 7, 7.7, 7.7] and [6.5, 6.5, 13, 14.3, 14.3]
#Because the PV cannot export to the grid when producing more than the load, the scenario reduces the amount of PV developed to 7
#LCC is now 2.75*7 + 0.5 *(0.7 = 0.7) + 0.5 * (6 + 7.3 + 7.3) = 30.25
scenario_specific_changes = JSON.parsefile("../test/Inputs/Multiple_Scenarios_Test_Scenario_Inputs.json")
m = Model(Optimizer_Type)
params = initialize_system(m, "../test/Inputs/Multiple_Scenarios_Test.json")
grid_scenario_vals = initialize_grid_scenarios(m, "../test/Inputs/Multiple_Scenarios_Test.json", params, scenario_specific_changes)
@objective(m, Min, params["system_cost"] + grid_scenario_vals.costs)
optimize!(m)
println("System cost is $(objective_value(m))", ". Should be 30.25")
println("PV value is: ", value(m[:dv_pv_kw]), ". Should be 7.0")

# #Can be used to print values
# print(m)
# vars = all_variables(m)
# M = Dict(zip(vars, value.(vars)))
# for (key, var) in M
#     println(key, ": ", var)
# end
#
#______________________________________________________________________________________
#Load is [2,3,4,5,6]
#grid value is 1 for each hour, solar cost is 5, battery cost is 1 per kw, 1 per kWh
#Outages occurr with 40% chance in each hour, and have a 50% chance of lasting 1 or two hours each.
#The value of lost load is 3/kWh
#Objective function is 3*5 for solar + 3*1 + 5*1 for battery + 1 for grid purchase in hour 3 = 24

m = Model(Optimizer_Type)
params = initialize_system(m, "../test/Inputs/Outages.json")
grid_scenario_vals = initialize_grid_scenarios(m, "../test/Inputs/Outages.json", params)
outage_scenario_vals = initialize_outage_events(m, "../test/Inputs/Outages.json",
 params, Dict("dv_stored_energy"=>grid_scenario_vals.system_state["dv_stored_energy"]))
# println(params["system_cost"])
# println(scenario_vals["costs"])

@objective(m, Min, params["system_cost"] + grid_scenario_vals.costs + outage_scenario_vals.costs)
optimize!(m)
println("LCC is: ", objective_value(m), ". Should be 24")


println("PV: ", value(m[:dv_pv_kw]), ". Value should be Should be 3.0")
println("Storage kw: ", value(m[:dv_storage_kw]), ". Value should be 3.0")
println("Storage kWh: ", value(m[:dv_storage_kwh]), ". Value should be 5.0")
# print(m)
# vars = all_variables(m)
# M = Dict(zip(vars, value.(vars)))
# for (key, var) in M
#     println(key, ": ", var)
# end
#______________________________________________________________________________________
#More complex run. Complex tariff with 9 potential load scaling and pv scaling probs
#Complex tariff (demand charges and tou demand rates), and PV + storage
m = Model(Optimizer_Type)
params = initialize_system(m, "../test/Inputs/pv_storage.json")
grid_scenario_vals = initialize_grid_scenarios(m, "../test/Inputs/pv_storage.json", params, JSON.parsefile("../test/Inputs/Large_Test_Scenario_Inputs.json"))
@objective(m, Min, params["system_cost"] + grid_scenario_vals.costs)
# @objective(m, Min, params["system_cost"] + grid_scenario_vals.costs + outage_scenario_vals)

tstart = time()
optimize!(m)

println("Time to optimize model was: ", time() - tstart)
println("LCC is: ",  round(objective_value(m); digits = 0), ". Compared to 1.2388763e7 for single scenario case") #Not checked
println("PV: ", round(value(m[:dv_pv_kw]); digits = 2), ". Should be same as single scenario case of 216.67 due to roof space + land constraint") #Not checked
println("Storage kw: ", round(value(m[:dv_storage_kw]); digits = 2), ". Compare to 55.88 for single scenario case") #Not checked
println("Storage kWh: ", round(value(m[:dv_storage_kwh]); digits = 2), ". Compare to 78.91 for single scenario case") #Not checked
