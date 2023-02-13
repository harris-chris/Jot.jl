using Jot

include("./performance_test_script_setup.jl")

(local_image_uncompiled,
lambda_function_uncompiled,
local_image_compiled,
lambda_function_compiled) = setup_images_and_functions()

# Get the average run times for the uncompiled local image:
repeat_num = 5
test_arg = [1, 2]
expected_response = [2, 3]

total_run_time = 0.0
for num = 1:repeat_num
  this_run_time = redirect_stdio(stdout=devnull, stderr=devnull) do
    run_local_image_test(
      local_image_uncompiled, test_arg, expected_response
    ) |> last
  end
  global total_run_time += this_run_time
end
average_uncompiled_run_time = total_run_time / repeat_num
@info "Average function run time for uncompiled local image was $average_uncompiled_run_time"

# Get the average run times for the compiled local image:
total_run_time = 0.0
for num = 1:repeat_num
  this_run_time = redirect_stdio(stdout=devnull, stderr=devnull) do
    run_local_image_test(
      local_image_compiled, test_arg, expected_response
    ) |> last
  end
  global total_run_time += this_run_time
end
average_compiled_run_time = total_run_time / repeat_num
@info "Average function run time for compiled local image was $average_compiled_run_time"

# Get the average run times for the uncompiled lambda function:
total_run_time = 0.0
for num = 1:repeat_num
  test_log = redirect_stdio(stdout=devnull, stderr=devnull) do
    run_lambda_function_test(
      lambda_function_uncompiled, test_arg, expected_response
    ) |> last
  end
  this_run_time = get_invocation_run_time(test_log)
  global total_run_time += this_run_time
end

average_uncompiled_run_time = total_run_time / repeat_num
@info "Average function run time for uncompiled lambda function was $average_uncompiled_run_time"

# Get the average run times for the compiled lambda function:
total_run_time = 0.0
for num = 1:repeat_num
  test_log = redirect_stdio(stdout=devnull, stderr=devnull) do
    run_lambda_function_test(
      lambda_function_compiled, test_arg, expected_response
    ) |> last
  end
  this_run_time = get_invocation_run_time(test_log)
  global total_run_time += this_run_time
end

average_compiled_run_time = total_run_time / repeat_num
@info "Average function run time for compiled lambda function was $average_compiled_run_time"


# invoke_function_with_log

# show_log_events(log)

# get_invocation_time_breakdown(log)
