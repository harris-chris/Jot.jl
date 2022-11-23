using Pkg

Pkg.develop(path="./")
using Jot

println("$JOT_OBSERVATION")

f = get_lambda_function("jottest1")
(res, log) = invoke_function_with_log(Dict("double"=>2), f)
@show log
show_observations(log)

