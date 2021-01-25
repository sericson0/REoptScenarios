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

println("Optimized. Objective value is ", round(objective_value(m); digits=  2), ". should be 35")
println("Generator size is: ", round(value(m[:dv_generator_kw]); digits = 2), ". Should be 8")
vars = all_variables(m)
var_names = name.(vars)
M = Dict(zip(var_names, value.(vars)))

for v in sort(var_names)
    println(v, ": ", M[v])
end
#______________________________________________________________________________________
