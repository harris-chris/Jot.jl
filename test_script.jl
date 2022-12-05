using Pkg

Pkg.develop(path="./")
using Jot

println("$JOT_OBSERVATION")

f = get_lambda_function(ARGS[begin])
(res, log) = invoke_function_with_log(Dict("double"=>2), f)
@info "function returned result $res"
@info "request_id"
@show log.RequestId
@info "\nShowing events"
foreach(log.cloudwatch_log_events) do event
  println(event)
end

println("Function run time was $(get_invocation_run_time(log))")
println("Precompile time was $(get_total_precompile_time(log))")
show_observations(log)

