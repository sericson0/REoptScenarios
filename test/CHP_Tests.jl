# using GLPK
using Gurobi
using DataFrames
# import CSV
# using Revise
#Ran tests using Gurobi. Pick your favorite optimizer and have fun
Optimizer_Type = Gurobi.Optimizer

import JSON
# import CSV
cd(joinpath(dirname(dirname(@__FILE__)), "src"))

Pkg.activate(".")
include("../src/REoptScenarios.jl")
using .REoptScenarios

cd(dirname(@__FILE__))
results = run_reopt("./inputs/test_chp.json", Optimizer_Type)

display(results["system"])
display(results["grid_connected"]["grid_scenario"]["chp"])

x = results["grid_connected"]["grid_scenario"]["resource_adequacy"]["lookback_hours"]
println(results["grid_connected"]["grid_scenario"]["grid_purchases"]["load_timeseries"][Int.(x)])
println(results["grid_connected"]["grid_scenario"]["grid_purchases"]["load_timeseries"][Int.(results["grid_connected"]["grid_scenario"]["resource_adequacy"]["event_hours"])])

display(results["system"])



y = 4955
println(results["grid_connected"]["grid_scenario"]["grid_purchases"]["load_timeseries"][y])

println(results["grid_connected"]["grid_scenario"]["pv"]["generation_timeseries"][4984:5000])
