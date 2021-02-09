# using GLPK
using Gurobi
using DataFrames
import CSV
#Ran tests using Gurobi. Pick your favorite optimizer and have fun
Optimizer_Type = Gurobi.Optimizer

import JSON
# import CSV
cd(joinpath(dirname(dirname(@__FILE__)), "src"))

Pkg.activate(".")
include("../src/REoptScenarios.jl")
using .REoptScenarios

cd(dirname(@__FILE__))

solar_profiles = CSV.read("./Inputs/SolarYears.csv", DataFrame)

inputs = JSON.parsefile("./inputs/Multiple_Solar_Profiles.json")
inputs["PV"]["production_factor"] = solar_profiles.Avg

results1 = run_reopt(inputs, Optimizer_Type)

solar_profile_runs = Dict()
for i in 2:(ncol(solar_profiles)-1)
    solar_profile_runs["SolarProfile_"*string(i-1)] = Dict("pv_prod_factor" => solar_profiles[:, i], "scenario_prob"=> 1/(ncol(solar_profiles)-2))
end

results2 = run_reopt( inputs, Optimizer_Type;  additional_scenario_inputs = solar_profile_runs)
println("_____________________________________________________________________\n\n\n\n")
println("System size using averages")
display(results1["system"])
println("LCC: ", results1["LCC"])


println("\n_____________________________________________________________________\n")
println("System size using all solar years")
display(results2["system"])
println("LCC: ", results2["LCC"])

# save_results(results, "../test/test outputs")
