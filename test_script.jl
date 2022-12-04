using Pkg

Pkg.develop(path="./")
using Jot

println("$JOT_OBSERVATION")

f = get_lambda_function("jottest1")
(res, log) = invoke_function_with_log(Dict("double"=>2), f)
@info "debug events"
@show log.cloudwatch_log_debug_events
@info "user events"
@show log.cloudwatch_log_user_events
println("Function run time was $(get_invocation_run_time(log))")
show_observations(log)

