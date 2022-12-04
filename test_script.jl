using Pkg

Pkg.develop(path="./")
using Jot

println("$JOT_OBSERVATION")

f = get_lambda_function("jottest1")
(res, log) = invoke_function_with_log(Dict("double"=>2), f)
@info "function returned result $res"
@info "request_id"
@show log.RequestId
@info "\nShowing debug events"
foreach(log.cloudwatch_log_debug_events) do event
  println(event)
end

@info "\nShowing user events"
foreach(log.cloudwatch_log_user_events) do event
  println(event)
end
println("Function run time was $(get_invocation_run_time(log))")
show_observations(log)

