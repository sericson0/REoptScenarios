# import MathOptInterface
# const MOI = MathOptInterface
module REoptScenarios
    # cd(dirname(@__FILE__))

using JuMP, GLPK, HTTP, Parameters, Dates, DelimitedFiles
using Gurobi
using JuMP.Containers: DenseAxisArray
import JSON

include("./keys.jl")
include("./constants.jl")
include("./types.jl")

main = "./core"

for folder in readdir(main)
    for file in readdir(joinpath(main,folder))
        include(joinpath(main,folder, file))
    end
end

export
    initialize_parameters,
    initialize_system,
    initialize_grid_scenarios,
    initialize_outage_events,
    get_result_values,
    run_reopt
end
# end
