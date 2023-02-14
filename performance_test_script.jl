using Jot

include("./performance_test_script_setup.jl")

(local_image_uncompiled,
lambda_function_uncompiled,
local_image_compiled,
lambda_function_compiled) = setup_images_and_functions()

repeat_num = 5
test_arg = [1, 2]
expected_response = [2, 3]

# Checking the initial run times of lambda functions
@info uppercase("\nchecking the initial run times of lambda functions:")
uncompiled_first_run_log = get_lambda_function_test_log(
    lambda_function_uncompiled, test_arg, expected_response
)
first_run_run_time = get_invocation_run_time(uncompiled_first_run_log)
if was_lambda_function_started_from_cold(uncompiled_first_run_log)
  @info "First run of uncompiled function was from cold and took $first_run_run_time ms"
else
  @info "First run of uncompiled function was from warm and took $first_run_run_time ms"
end

compiled_first_run_log = get_lambda_function_test_log(
    lambda_function_compiled, test_arg, expected_response
)
first_run_run_time = get_invocation_run_time(compiled_first_run_log)
if was_lambda_function_started_from_cold(compiled_first_run_log)
  @info "First run of compiled function was from cold and took $first_run_run_time ms"
else
  @info "First run of compiled function was from warm and took $first_run_run_time ms"
end

# Show time breakdown of the initial compiled function run
@info uppercase("\nshowing the time breakdown of the initial compiled function run:")
compiled_run_time_breakdown = get_invocation_time_breakdown(compiled_first_run_log)
precompile_time = compiled_run_time_breakdown.precompile_time
pct_text = if precompile_time != 0.0
  precompile_pct = precompile_time / compiled_run_time_breakdown.total
  "($precompile_pct of total run time of $(compiled_run_time_breakdown.total))"
else
  ""
end
@info "Compiled function spent $precompile_time ms precompiling $pct_text"

# Get the average run times for the uncompiled local image:
@info uppercase("\ngetting the average run times for the uncompiled local image:")
total_run_time = 0.0
for num = 1:repeat_num
  global total_run_time += get_local_image_run_time(
    local_image_uncompiled, test_arg, expected_response
  )
  sleep(1)
end
average_uncompiled_run_time = total_run_time / repeat_num
@info "Average function run time for uncompiled local image was $average_uncompiled_run_time"

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

# Get the average run times for the uncompiled lambda function:
sleep(15)
@info uppercase("\ngetting the average run times for the uncompiled lambda function:")
total_run_time = 0.0
for num = 1:repeat_num
  test_log = get_lambda_function_test_log(
    lambda_function_uncompiled, test_arg, expected_response
  )
  run_time = get_invocation_run_time(test_log)
  @show run_time
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
  @show run_time
  global total_run_time += run_time
  sleep(10)
end

average_compiled_run_time = total_run_time / repeat_num
@info "Average function run time for compiled lambda function was $average_compiled_run_time"

# invoke_function_with_log

# show_log_events(log)

# get_invocation_time_breakdown(log)
