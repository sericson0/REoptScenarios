#Replace TARRIFF with struct name (upper camel case) and tariff with function name (lowercase underscore)
@with_kw struct TARIFF
    #TARIFF parameters go here
end
##

function setup_tariff_inputs(value_dic::Dict, params::Dict)
    #convert inputs (value_dic) to dictionary which has keys for each struct value
end



function tariff_scenario(m::JuMP.AbstractModel, grid_purchases, scenario::Scenario, params::Dict)
    #grid_purchases is a JuMP array of variables of kWh purchased from the grid
    #Adds costs or credits for given scenario
    tariff_return_vals = Dict()
    costs = 0
    #Tariff code goes here. update tariff_return_vals and costs


    add_scenario_results(params["results"], scenario, "tariff"; cost = costs, other_results = tariff_return_vals)
    #Can return additional load or
    return (costs = costs, )
end
