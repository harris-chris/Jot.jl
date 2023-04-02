using PackageCompiler

const SYSIMAGE_FNAME = "SysImage.so"

"""
    struct FunctionTestData
      test_argument::Any
      expected_response::Any
    end

A simple data structure that contains a test argument for a given lambda function, and what return value is expected from the function if passed taht test argument. For example, if your responder function takes a `Vector{Int64}` and increments each element in the vector by 1, you might use `[1, 2]` as the `test_argument`, and `[2, 3]` as the `expected_response`.
"""
struct FunctionTestData
  test_argument::Any
  expected_response::Any
end

function get_jot_test_data()::FunctionTestData
  FunctionTestData(jot_test_string, jot_test_string * jot_test_string_response_suffix)
end

function create_jot_single_run_launcher_script!(
    responder::Responder,
    run_tests::Bool,
    single_run_timeout::Int64,
  )::String

  launcher_fname = "single_run_launcher.sh"
  precompile_from_run_fname = "precompile_statements_from_run.jl"
  precompile_from_tests_fname = "precompile_statements_from_tests.jl"

  response_function_name = String(responder.response_function)
  response_param_type = responder.response_function_param_type
  package_name = get_package_name(responder)

  julia_start_runtime_command =
    "start_runtime(" *
    join([
      "\\\"\$LAMBDA_ENDPOINT\\\"",
      "$package_name.$response_function_name",
      "$response_param_type",
    ], ", ") *
    ")"

  julia_exec_statements = [
    "using Jot",
    "using $package_name",
    julia_start_runtime_command,
  ]
  julia_exec = join(julia_exec_statements, "; ")

  run_julia_rie_cmd =
    "timeout $(single_run_timeout)s " *
    "./aws-lambda-rie julia " *
    "--project=. " *
    "--trace-compile=$precompile_from_run_fname " *
    "-e \"$julia_exec\""

  script_body = """
  #!/bin/bash
  LAMBDA_ENDPOINT="127.0.0.1:9001"
  $run_julia_rie_cmd
  """

  tests_path = joinpath(package_name, "test", "runtests.jl")
  addnl_for_tests = if run_tests
    if !isfile(tests_path)
      error(
        "create_local_image has been called with run_tests_during_package_compile=" *
        "true for $package_name but could not find a test/runtests.jl file"
      )
    end
    """
    julia --project=$package_name \
        --trace-compile=$precompile_from_tests_fname \
        $tests_path
    cat $precompile_from_tests_fname >> precompile_statements_temp.jl
    cat $precompile_from_run_fname >> precompile_statements_temp.jl
    mv precompile_statements_temp.jl $precompile_statements_fname
    """
  else
    """
    cat $precompile_from_run_fname >> $precompile_statements_fname
    """
  end

  script_all = script_body * addnl_for_tests

  open(launcher_fname, "w") do f
    write(f, script_all)
  end
  launcher_fname
end

function create_precompile_statements_file!(
    responder::Responder,
    function_test_data::Union{Nothing, FunctionTestData},
    run_tests::Bool,
  )::String
  precomp_timeout = 20; delay = 0.1
  launcher_script = create_jot_single_run_launcher_script!(
    responder, run_tests, precomp_timeout
  )

  stdout_buffer = IOBuffer(); stderr_buffer = IOBuffer()
  launcher_started = Base.Event()
  launcher_cmd = pipeline(
    `sh $launcher_script`; stdout=stdout_buffer, stderr=stderr_buffer
  )
  launcher_process = open(launcher_cmd)
  @info "Waiting for AWS RIE to start up ..."

  stdout_read = String(""); stderr_read = String("")
  while true
    stdout_read = stdout_read * String(take!(stdout_buffer))
    stderr_read = stderr_read * String(take!(stderr_buffer))
    if was_port_in_use(stderr_read)
      error("Port 8080 was already in use by another process")
    elseif did_launcher_run(stderr_read)
      @info "... AWS RIE has started up"
      break
    else
      sleep(0.1)
    end
  end

  @info "Making local responder invocation ..."
  test_data = isnothing(function_test_data) ? get_jot_test_data() : function_test_data

  response = send_local_request(test_data.test_argument; local_port = 8080)
  if response != test_data.expected_response
    error(
      "During package compilation, responder sent test response $response " *
      "when response $(test_data.expected_response) was expected"
    )
  else
    @info "... invocation received correct response $response from RIE server"
  end

  # Wait for the precompile statements file to exist
  @info "Waiting for $precompile_statements_fname to be generated..."
  while true
    isfile(precompile_statements_fname) && break
    precomp_timeout = precomp_timeout - delay
    if precomp_timeout == 0.
      error("Timed out waiting for $precompile_statements_fname to generate")
    end
    sleep(delay)
  end
  @info "... $precompile_statements_fname has been generated"
  kill(launcher_process)

  precompile_statements_fname
end

function did_launcher_run(stdout_text::String)::Bool
  occursin("start_runtime", stdout_text)
end

function was_port_in_use(stderr_text::String)::Bool
  occursin("bind: address already in use", stderr_text)
end

