test_arg = [1, 2]
expected_response = [2, 3]

function setup_images_and_functions(
  )::Tuple{LocalImage, LambdaFunction, LocalImage, LambdaFunction}
  name_prefix = "increment-vector"
  uncompiled_image = get_or_create_local_image(name_prefix, false)
  uncompiled_lambda = get_or_create_lambda_function(name_prefix, false)
  compiled_image = get_or_create_local_image(name_prefix, true)
  compiled_lambda = get_or_create_lambda_function(name_prefix, true)
  (uncompiled_image, uncompiled_lambda, compiled_image, compiled_lambda)
end

function get_or_create_local_image(name_prefix::String, compile::Bool)::LocalImage
  name_suffix = compile ? "compiled" : "uncompiled"
  image_opt = get_local_image("$name_prefix-$name_suffix")
  open("increment_vector.jl", "w") do f
    write(f, "increment_vector(v::Vector{Int}) = map(x -> x + 1, v)")
  end
  increment_responder = get_responder("./increment_vector.jl", :increment_vector, Vector{Int})
  if isnothing(image_opt)
    create_local_image(
      increment_responder;
      image_suffix="$name_prefix-$name_suffix",
      package_compile=compile,
    )
  else
    image_opt
  end
end

function get_or_create_lambda_function(name_prefix::String, compile::Bool)::LambdaFunction
  name_suffix = compile ? "compiled" : "uncompiled"
  lambda_opt = get_lambda_function("$name_prefix-$name_suffix")
  if isnothing(lambda_opt)
    local_image = get_or_create_local_image(name_prefix, compile)
    remote_image = push_to_ecr!(local_image)
    lf = create_lambda_function(remote_image)
    # The first run of a new function seems to take unusually long, so we just get this
    # out the way and discard the results as it's unrepresentative
    _ = get_lambda_function_test_log(
        lf, test_arg, expected_response
    )
    sleep(15)
    lf
  else
    lambda_opt
  end
end

function get_local_image_run_time(
    image::LocalImage,
    test_arg::Any,
    expected_response::Any,
  )::Float64
  redirect_stdio(stdout=devnull, stderr=devnull) do
    run_local_image_test(
      image, test_arg, expected_response
    ) |> last
  end
end

function get_lambda_function_test_log(
    func::LambdaFunction,
    test_arg::Any,
    expected_response::Any,
  )::LambdaFunctionInvocationLog
  redirect_stdio(stdout=devnull, stderr=devnull) do
    run_lambda_function_test(
      func, test_arg, expected_response
    ) |> last
  end
end

function get_lambda_request_id(log::LambdaFunctionInvocationLog)::String
  request_id_msgs = filter(
    x -> occursin("JOT_AWS_LAMBDA_REQUEST_ID", x.message), log.cloudwatch_log_events
  )
  request_id_msgs[begin].message
end

function was_lambda_function_started_from_cold(
    log::LambdaFunctionInvocationLog,
  )::Bool
  from_cold_events = filter(log.cloudwatch_log_events) do ev
    occursin("Bootstrap started ...", ev.message, )
  end
  length(from_cold_events) > 1
end

function count_precompile_statements(
    log::LambdaFunctionInvocationLog,
  )::Int64
  precompile_events = filter(log.cloudwatch_log_events) do ev
    startswith(ev.message, "precompile(")
  end
  length(precompile_events)
end


