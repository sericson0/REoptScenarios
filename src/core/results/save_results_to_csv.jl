function save_results(results, folder)
    system = results["system"]
    system["LCC"] = results["LCC"]
    CSV.write(joinpath(folder, "system.csv"), system)
    time_series_len =  length(results["parameters"]["times"])

    if haskey(results, "grid_connected")
        mkpath(joinpath(folder, "grid connected"))
        for (scenario_name, scenario_vals) in results["grid_connected"]
            time_series_vals = Dict()
            single_vals = Dict()
            for (out_category_key, out_category_val) in scenario_vals
                for (key, val) in out_category_val
                    if length(val) > time_series_len
                        time_series_vals[out_category_key * "_" * key] = val[2:end]
                    elseif length(val) == time_series_len
                        time_series_vals[out_category_key * "_" * key] = val
                    elseif length(val) == 1
                        single_vals[out_category_key * "_" *key] = val
                    else
                        for (i, v) in enumerate(val)
                            single_vals[out_category_key * "_" * key * "_" * string(i)] = v
                        end
                    end
                end
            end
                CSV.write(joinpath(folder, "grid connected",scenario_name * " single_vals.csv"), single_vals)
                ts_df = DataFrame(time_series_vals)
                CSV.write(joinpath(folder, "grid connected", scenario_name * " timeseries.csv"), ts_df)
        end
    end

    if haskey(results, "events")
        mkpath(joinpath(folder, "events"))
        for (event_name, event_vals) in results["events"]
            CSV.write(joinpath(folder, "events", event_name) * ".csv", event_vals)
        end
    end
end
