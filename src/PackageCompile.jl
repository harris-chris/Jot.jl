using PackageCompiler

const PRECOMP_STATEMENTS_FNAME = "precompile_statements.jl"
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

function create_jot_single_run_launcher_script!(
    responder::LocalPackageResponder,
  )::String
  launcher_fname = "single_run_launcher.sh"
  cd(responder.build_dir) do
    bootstrap_prefix = """
    #!/bin/bash
    """

    bootstrap_body = get_bootstrap_body(
      responder,
      ["--trace-compile=$PRECOMP_STATEMENTS_FNAME", "--project=."];
      timeout = 60,
    )

    bootstrap_all = bootstrap_prefix * bootstrap_body

    open(launcher_fname, "w") do f
      write(f, bootstrap_all)
    end
  end
  launcher_fname
end

function create_precompile_statements_file!(
    responder::LocalPackageResponder,
    function_test_data::FunctionTestData,
  )::String
  launcher_script = create_jot_single_run_launcher_script!(responder)
  stdout_buffer = IOBuffer(); stderr_buffer = IOBuffer()
  launcher_started = Base.Event()
  launcher_process = cd(responder.build_dir) do
    launcher_cmd = pipeline(
      `sh $launcher_script`; stdout=stdout_buffer, stderr=stderr_buffer
    )
    launcher_process = open(launcher_cmd)
    launcher_process
  end
  @info "Waiting for AWS RIE to start up ..."

  stdout_read = String(""); stderr_read = String("")
  while true
    stdout_read = stdout_read * String(take!(stdout_buffer))
    stderr_read = stderr_read * String(take!(stderr_buffer))
    if was_port_in_use(stderr_read)
      error("Port 8080 was already in use by another process")
    elseif did_launcher_run(stdout_read)
      @info "... AWS RIE has started up"
      break
    else
      sleep(0.1)
    end
  end

  @info "Making local responder invocation ..."
  response = send_local_request(function_test_data.test_argument; local_port = 8080)

  if response != function_test_data.expected_response
    error(
      "During package compilation, responder sent test response $response " *
      "when $(function_test_data.expected_response) was expected"
    )
  else
    @info "... invocation received correct response $response from RIE server"
  end

  # Wait for the precompile statements file to exist
  @info "Waiting for $PRECOMP_STATEMENTS_FNAME to be generated..."
  precomp_timeout = 20.; delay = 0.1
  while true
    isfile(joinpath(responder.build_dir, PRECOMP_STATEMENTS_FNAME)) && break
    precomp_timeout = precomp_timeout - delay
    if precomp_timeout == 0.
      error("Timed out waiting for $PRECOMP_STATEMENTS_FNAME to generate")
    end
    sleep(delay)
  end
  @info "... $PRECOMP_STATEMENTS_FNAME has been generated"
  kill(launcher_process)
  PRECOMP_STATEMENTS_FNAME
end

function did_launcher_run(stdout_text::String)::Bool
  occursin("start_runtime", stdout_text)
end

function was_port_in_use(stderr_text::String)::Bool
  occursin("bind: address already in use", stderr_text)
end

