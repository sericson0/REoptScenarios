#TODO Needs to be updated to reflect recent changes

#Technology code framework for given technology TECH

#struct
@with_kw mutable struct TECH
    #set of technology parameters
end
##
function TECH_system(m, input_dic, financial)
    #TECH_system initializes the system struct which includes relevant TECH parameters,
    #and adds the technology sizing variables to the model
    #Also calculates capital + o&m costs and outputs these variables in a named list

    #m is the model, input_dic is a dictionary of inputs from a json, financial is from a financial struct
    TECH_struct_instance = initialize_with_inputs(input_dic, TECH, "TECH input name in json", setup_TECH_inputs, validate_TECH_args)
    #setup_TECH_inputs and validate_TECH_args are optional
    #initialize_with_inputs takes relevant inputs and instantiates a struct instance

    @variable(m, TECH_struct_instance.min_kw <= dv_TECH_kw <= TECH_struct_instance.max_kw)
    #adds TECH size to model. Because is a named variable other functions can access dv_TECH_kw directly with m[:dv_TECH_kw]
    #If additional variables, such as dv_TECH_kwh are required they are added here

    cost = TECH_cost(m, TECH_struct_instance, financial)
    #cost includes capital costs and present worth of O&M costs
    return (struct_instance = pv, sys_cost = cost)
end
##

function TECH_scenario(m, tech_struct_instance, scenario, additional_inputs)
    #Technology generation
    TECH_generation = @variable(m, [scenario_struct_instance.times], base_name = "dv_TECH_generation$(scenario_struct_instance.name)")
    #If the technology draws from the grid, such as with battery storage, then those variables go here
    TECH_load = []

    @constraint(m, [ts in scenario.times], TECH_output[ts] <= m[:dv_TECH_kw])
    #Additional constraints for dispatch go here

    dispatch_costs = 0
    #Dispatch costs such as fuel use go here
    return (gen = TECH_generation, load = TECH_load, cost = dispatch_costs)
end
##

function TECH_cost(m, TECH_struct_instance, financial)
    effective_cost_per_kw = effective_cost(;
                #inputs for effective cost for technology
            )
    capital_costs = effective_cost_per_kw * m[:dv_TECH_kw]
    #If other capital costs, such as per kWh, apply, those are added here
    om_costs = financial.pwf_om * pv.om_cost_per_kw * m[:dv_TECH_kw]
    return financial.two_party_factor * (capital_costs + om_costs)
end
##

function setup_TECH_inputs(value_dic, input_dic)
    #value_dic is a dictionary of user inputs and default values for the TECH
    #input_dic includes all inputs from the user
    #This code should add or change any of the values in value_dic such that
    #all parameters in the TECH_struct are included as keys in the dictionary with valid values
    return value_dic
end
##

function validate_pv_args(TECH_struct_instance::TECH)
  invalid_args = String[]
  #Check if any of the parameters in the tech struct are not valid inputs. Code is optional

  # if TECH param out of range
      # push!(invalid_args, "TECH param must be within range [range], got $(tech_param)")
  # end
  if length(invalid_args) > 0
      error("Invalid argument values: $(invalid_args)")
  end
end


##
#Any additional helper functions go here
