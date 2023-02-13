using Jot

include("./performance_test_script_setup.jl")

(local_image_uncompiled,
lambda_function_uncompiled,
local_image_compiled,
lambda_function_compiled) = setup_images_and_functions()

repeat_num = 5
test_arg = [1, 2]
expected_response = [2, 3]

uncompiled_first_run_log = get_lambda_function_test_log(
    lambda_function_uncompiled, test_arg, expected_response
)
first_run_run_time = get_invocation_run_time(uncompiled_first_run_log)
if was_lambda_function_started_from_cold(uncompiled_first_run_log)
  @info "First run of uncompiled function was from cold and took $first_run_run_time ms"
else
  @info "First run of uncompiled function was from warm and took $first_run_run_time ms"
end

# Check the initial run times
compiled_first_run_log = get_lambda_function_test_log(
    lambda_function_compiled, test_arg, expected_response
)
first_run_run_time = get_invocation_run_time(compiled_first_run_log)
if was_lambda_function_started_from_cold(compiled_first_run_log)
  @info "First run of compiled function was from cold and took $first_run_run_time ms"
else
  @info "First run of compiled function was from warm and took $first_run_run_time ms"
end

# Show time breakdown
compiled_run_time_breakdown = get_invocation_time_breakdown(compiled_first_run_log)
precompile_time = compiled_run_time_breakdown.precompile_time
pct_text = if precompile_time != 0.0
  precompile_pct = compiled_run_time_breakdown.total / precompile_time
  "($precompile_pct of total run time)"
else
  ""
end
@info "Compiled function spent $precompile_time ms precompiling $pct_text"

# Get the average run times for the uncompiled local image:
total_run_time = 0.0
for num = 1:repeat_num
  global total_run_time += get_local_image_run_time(
    local_image_uncompiled, test_arg, expected_response
  )
end
average_uncompiled_run_time = total_run_time / repeat_num
@info "Average function run time for uncompiled local image was $average_uncompiled_run_time"

# Get the average run times for the compiled local image:
total_run_time = 0.0
for num = 1:repeat_num
  global total_run_time += get_local_image_run_time(
    local_image_compiled, test_arg, expected_response
  )
end
average_compiled_run_time = total_run_time / repeat_num
@info "Average function run time for compiled local image was $average_compiled_run_time"

# Get the average run times for the uncompiled lambda function:
total_run_time = 0.0
for num = 1:repeat_num
  test_log = get_lambda_function_test_log(
    lambda_function_uncompiled, test_arg, expected_response
  )
  global total_run_time += get_invocation_run_time(test_log)
end

average_uncompiled_run_time = total_run_time / repeat_num
@info "Average function run time for uncompiled lambda function was $average_uncompiled_run_time"

# Get the average run times for the compiled lambda function:
total_run_time = 0.0
for num = 1:repeat_num
  test_log = get_lambda_function_test_log(
    lambda_function_compiled, test_arg, expected_response
  )
  global total_run_time += get_invocation_run_time(test_log)
end

average_compiled_run_time = total_run_time / repeat_num
@info "Average function run time for compiled lambda function was $average_compiled_run_time"

# invoke_function_with_log

# show_log_events(log)

# get_invocation_time_breakdown(log)
