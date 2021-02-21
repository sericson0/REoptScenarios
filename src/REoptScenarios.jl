# import MathOptInterface
# const MOI = MathOptInterface
module REoptScenarios
    # cd(dirname(@__FILE__))

using JuMP, GLPK, HTTP, Parameters, Dates, DelimitedFiles, DataFrames
using JuMP.Containers: DenseAxisArray
import JSON, CSV

include("./keys.jl")
include("./types.jl")

main = "./core"

for folder in readdir(main)
    for file in readdir(joinpath(main,folder))
        include(joinpath(main,folder, file))
    end
end

export
    run_reopt,
    save_results
end
# end
