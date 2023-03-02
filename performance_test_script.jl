using Jot

include("./performance_test_script_setup.jl")

# (local_image_uncompiled,
# lambda_function_uncompiled,
(local_image_compiled,
lambda_function_compiled) = setup_images_and_functions()

repeat_num = 5

# Get the average run times for the uncompiled local image:
# @info uppercase("\ngetting the average run times for the uncompiled local image:")
# total_run_time = 0.0
# for num = 1:repeat_num
#   global total_run_time += get_local_image_run_time(
#     local_image_uncompiled, test_arg, expected_response
#   )
#   sleep(1)
# end
# average_uncompiled_run_time = total_run_time / repeat_num
# @info "Average function run time for uncompiled local image was $average_uncompiled_run_time"

# Get the average run times for the compiled local image:
@info uppercase("\ngetting the average run times for the compiled local image:")
total_run_time = 0.0
for num = 1:repeat_num
  global total_run_time += get_local_image_run_time(
    local_image_compiled, test_arg, expected_response
  )
  sleep(1)
end
average_compiled_run_time = total_run_time / repeat_num
@info "Average function run time for compiled local image was $average_compiled_run_time"

# # Do a run of the uncompiled function
# uncompiled_log = get_lambda_function_test_log(
#     lambda_function_uncompiled, test_arg, expected_response
# )

# # Show time breakdown of the uncompiled function run
# @info uppercase("\nshowing the time breakdown of the initial uncompiled function run:")
# uncompiled_run_time_breakdown = get_invocation_time_breakdown(uncompiled_log)
# precompile_time = uncompiled_run_time_breakdown.precompile_time
# request_id = get_lambda_request_id(uncompiled_log)
# pct_text = if precompile_time != 0.0
#   precompile_pct = precompile_time / uncompiled_run_time_breakdown.total
#   "($precompile_pct of total run time of $(uncompiled_run_time_breakdown.total))"
# else
#   ""
# end
# @info "Uncompiled function with request id $request_id spent $precompile_time ms precompiling $pct_text"
# @info "Uncompiled function with request id $request_id had $(count_precompile_statements(uncompiled_log)) precompiles"

# Do a run of the compiled function
compiled_log = get_lambda_function_test_log(
    lambda_function_compiled, test_arg, expected_response
)

# Show time breakdown of the compiled function run
@info uppercase("\nshowing the time breakdown of the initial compiled function run:")
compiled_run_time_breakdown = get_invocation_time_breakdown(compiled_log)
precompile_time = compiled_run_time_breakdown.precompile_time
request_id = get_lambda_request_id(compiled_log)
pct_text = if precompile_time != 0.0
  precompile_pct = precompile_time / compiled_run_time_breakdown.total
  "($precompile_pct of total run time of $(compiled_run_time_breakdown.total))"
else
  ""
end
@info "Compiled function with request id $request_id spent $precompile_time ms precompiling $pct_text"
@info "Compiled function with request id $request_id had $(count_precompile_statements(compiled_log)) precompiles"

sleep(15)

# Get the average run times for the uncompiled lambda function:
@info uppercase("\ngetting the average run times for the uncompiled lambda function:")
total_run_time = 0.0
for num = 1:repeat_num
  @info "running function"
  test_log = get_lambda_function_test_log(
    lambda_function_uncompiled, test_arg, expected_response
  )
  run_time = get_invocation_run_time(test_log)
  @info "Request id: $(get_lambda_request_id(test_log)) took $run_time"
  global total_run_time += run_time
  sleep(10)
end

average_uncompiled_run_time = total_run_time / repeat_num
@info "Average function run time for uncompiled lambda function was $average_uncompiled_run_time"

# Get the average run times for the compiled lambda function:
@info uppercase("\ngetting the average run times for the compiled lambda function:")
total_run_time = 0.0
for num = 1:repeat_num
  test_log = get_lambda_function_test_log(
    lambda_function_compiled, test_arg, expected_response
  )
  run_time = get_invocation_run_time(test_log)
  @info "Request id: $(get_lambda_request_id(test_log)) took $run_time"
  global total_run_time += run_time
  sleep(10)
end

average_compiled_run_time = total_run_time / repeat_num
@info "Average function run time for compiled lambda function was $average_compiled_run_time"

# invoke_function_with_log

# show_log_events(log)

# get_invocation_time_breakdown(log)
