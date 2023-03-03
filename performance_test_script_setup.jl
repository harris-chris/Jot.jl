using Jot
using Random

test_arg = [1, 2]
expected_response = [2, 3]

function setup_images_and_functions(
  )::Tuple{LocalImage, LambdaFunction, LocalImage, LambdaFunction}
  this_rand_string = this_random_string = randstring(8) |> lowercase
  name_prefix = "performance-test-$this_rand_string"
  responder, function_test_data = create_test_responder(this_rand_string)
  uncompiled_name, uncompiled_local_image = create_test_local_image(
    name_prefix, responder, nothing, false
  )
  uncompiled_lambda = create_test_lambda_function(
    uncompiled_name, uncompiled_local_image
  )
  compiled_name, compiled_local_image = create_test_local_image(
    name_prefix, responder, function_test_data, true
  )
  compiled_lambda = create_test_lambda_function(
    compiled_name, compiled_local_image
  )
  (uncompiled_local_image, uncompiled_lambda, compiled_local_image, compiled_lambda)
end

function create_test_responder(
    rand_string::String,
  )::Tuple{LocalPackageResponder, FunctionTestData}
  open("responder_script.jl", "w") do f
    write(f, "respond(v::Vector{Int}) = map(x -> x + 1, v)")
  end
  responder = get_responder("./responder_script.jl", :respond, Vector{Int})
  test_argument = [1, 2]
  expected_response = [2, 3]
  function_test_data = FunctionTestData(test_argument, expected_response)
  (responder, function_test_data)
end

function create_test_local_image(
    name_prefix::String,
    responder::LocalPackageResponder,
    function_test_data::Union{Nothing, FunctionTestData},
    package_compile::Bool,
  )::Tuple{String, LocalImage}
  name_suffix = isnothing(function_test_data) ? "uncompiled" : "compiled"
  name = "$name_prefix-$name_suffix"
  li = create_local_image(
    responder;
    image_suffix=name,
    function_test_data=function_test_data,
    package_compile=package_compile,
  )
  (name, li)
end

function create_test_lambda_function(
    name::String,
    local_image::LocalImage,
  )::LambdaFunction
  remote_image = push_to_ecr!(local_image)
  lf = create_lambda_function(remote_image)
  # The first run of a new function seems to take unusually long, so we just get this
  # out the way and discard the results as it's unrepresentative
  test_log = get_lambda_function_test_log(
      lf, test_arg, expected_response
  )
  @info "Function $name created, first run had $(count_precompile_statements(test_log)) precompiles"
  lf
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


