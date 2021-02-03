using JuMP
# using GLPK
using Gurobi
#Ran tests using Gurobi. Pick your favorite optimizer and have fun
# Optimizer_Type = Gurobi.Optimizer

import JSON
# import CSV
cd(joinpath(dirname(dirname(@__FILE__)), "src"))
Pkg.activate(".")
include("../src/REoptScenarios.jl")
using .REoptScenarios

Optimizer_Type = Gurobi.Optimizer
#______________________________________________________________________________________________________
results = run_reopt("../test/Inputs/monthly_rate.json", Optimizer_Type)

println("Optimized. Objective value is ", results["LCC"], ". should be 437169.27")
println("PV size is: ", results["system"]["pv_kw"], ". Should be 64.251")

#______________________________________________________________________________________________________

results = run_reopt("../test/Inputs/pv_storage.json", Optimizer_Type)
println("LCC is: ",  results["LCC"], " Value should be 1.2388763e7")
println("PV: ", results["system"]["pv_kw"], ". Value should be Should be 216.67")
println("Storage kw: ", results["system"]["storage_kw"], ". Value should be 55.885")
println("Storage kWh: ", results["system"]["storage_kwh"], ". Value should be 78.911")
#______________________________________________________________________________________
#Tests the multiple scenarios approach
#Single year with no incentives or taxes.
#Uses "PV", but with production factor set to 1.
#PV cost is 2.75, and energy cost is 1.
#base load is [5, 5, 10, 11, 11].
#With single scenario optimal PV is 10 and lcc is 2.75*10 + 2*1 = 29.5
results = run_reopt("../test/Inputs/Multiple_Scenarios_Test.json", Optimizer_Type)
println("System cost is ", results["LCC"], ". Should be 29.5")
println("PV value is: ", results["system"]["pv_kw"], ". Should be 10.0")


#Now we are going run with two scenarios, one where the load is 30% smaller and one where load is 30% larger.
#Load is now [3.5, 3.5, 7, 7.7, 7.7] and [6.5, 6.5, 13, 14.3, 14.3]
#Because the PV cannot export to the grid when producing more than the load, the scenario reduces the amount of PV developed to 7
#LCC is now 2.75*7 + 0.5 *(0.7 = 0.7) + 0.5 * (6 + 7.3 + 7.3) = 30.25
results = reun_reopt("../test/Inputs/Multiple_Scenarios_Test_Scenario_Inputs.json"; additional_scenario_inputs = "../test/Inputs/Multiple_Scenarios_Test_Scenario_Inputs.json")
println("System cost is ",results["LCC"], ". Should be 30.25")
println("PV value is: ", results["system"]["pv_kw"], ". Should be 7.0")

#______________________________________________________________________________________
#Load is [2,3,4,5,6]
#grid value is 1 for each hour, solar cost is 5, battery cost is 1 per kw, 1 per kWh
#Outages occurr with 40% chance in each hour, and have a 50% chance of lasting 1 or two hours each.
#The value of lost load is 3/kWh
#Objective function is 3*5 for solar + 3*1 + 5*1 for battery + 1 for grid purchase in hour 3 = 24
results = run_reopt("../test/Inputs/Outages.json", Optimizer_Type)
println("LCC is: ", results["LCC"], ". Should be 24")
println("PV: ", results["system"]["pv_kw"], ". Value should be Should be 3.0")
println("Storage kw: ", results["system"]["storage_kw"], ". Value should be 3.0")
println("Storage kWh: ", results["system"]["storage_kwh"], ". Value should be 5.0")

#______________________________________________________________________________________
#More complex run. Complex tariff with 9 potential load scaling and pv scaling probs
#Complex tariff (demand charges and tou demand rates), and PV + storage
tstart = time()
results = run_reopt( "../test/Inputs/pv_storage.json", Optimizer_Type;  additional_scenario_inputs = "../test/Inputs/Large_Test_Scenario_Inputs.json")
println("Time to optimize model was: ", time() - tstart)



println("LCC is: ",  results["LCC"], ". Compared to 1.2388763e7 for single scenario case") #Not checked
println("PV: ", results["system"]["pv_kw"], ". Should be same as single scenario case of 216.67 due to roof space + land constraint") #Not checked
println("Storage kw: ", results["system"]["storage_kw"], ". Compare to 55.88 for single scenario case") #Not checked
println("Storage kWh: ", results["system"]["storage_kwh"], ". Compare to 78.91 for single scenario case") #Not checked

##
#Simple tariff and only Generator
results = run_reopt("../test/Inputs/Gen_Test.json", Optimizer_Type)

println("Optimized. Objective value is ", results["LCC"], ". should be 35.0")
println("Generator size is: ", results["system"]["generator_kw"], ". Should be 8.0")
