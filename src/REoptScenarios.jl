# import MathOptInterface
# const MOI = MathOptInterface
module REoptScenarios
    # cd(dirname(@__FILE__))

using JuMP, GLPK, HTTP, Parameters, Dates, DelimitedFiles
using JuMP.Containers: DenseAxisArray
import JSON

include("./keys.jl")
include("./constants.jl")

main = "./core"

for folder in readdir(main)
    for file in readdir(joinpath(main,folder))
        include(joinpath(main,folder, file))
    end
end

export
    initialize_system,
    initialize_grid_scenarios,
    initialize_outage_events
end
# end
