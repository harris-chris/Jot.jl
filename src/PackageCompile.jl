using PackageCompiler

const PRECOMP_STATEMENTS_FNAME = "precompile_statements.jl"
const SYSIMAGE_FNAME = "SysImage.so"

struct FunctionTestData
  test_argument::Any
  expected_response::Any
end

function create_jot_single_run_launcher_script!(
    responder::LocalPackageResponder,
  )::String
  jot_path = abspath(pwd())

  if !("aws-lambda-rie" in readdir())
    run(`curl -Lo ./aws-lambda-rie https://github.com/aws/aws-lambda-runtime-interface-emulator/releases/latest/download/aws-lambda-rie`)
    run(`chmod +x ./aws-lambda-rie`)
  end

  bootstrap_prefix = """
  #!/bin/bash
  """

  bootstrap_body = get_bootstrap_body(
    responder,
    ["--trace-compile=$PRECOMP_STATEMENTS_FNAME", "-i"];
    jot_path = jot_path,
    timeout = 60,
  )

  bootstrap_all = bootstrap_prefix * bootstrap_body

  fname = "single_run_launcher.sh"
  open(fname, "w") do f
    write(f, bootstrap_all)
  end
  fname
end

function create_precompile_statements_file!(
    responder::LocalPackageResponder,
    function_test_data::FunctionTestData,
  )::String
  launcher_script = create_jot_single_run_launcher_script!(responder)
  @info "Launcher script created in $(pwd())"
  @info "Starting launcher script..."
  stdout_buffer = IOBuffer(); stderr_buffer = IOBuffer()
  launcher_started = Base.Event()

  launcher_cmd = pipeline(`sh $launcher_script`; stdout=stdout_buffer, stderr=stderr_buffer)
  launcher_process = open(launcher_cmd)

  @info "Starting watcher processes..."
  stdout_read = String(""); stderr_read = String("")
  while true
    stdout_read = stdout_read * String(take!(stdout_buffer))
    stderr_read = stderr_read * String(take!(stderr_buffer))
    if was_port_in_use(stderr_read)
      error("Port 8080 was already in use by another process")
    elseif did_launcher_run(stdout_read)
      break
    else
      sleep(0.1)
    end
  end

  # @info "... waiting for launcher to start ..."
  # wait(launcher_started)
  # close(Base.pipe_writer(stdout_pipe))
  # close(Base.pipe_writer(stderr_pipe))
  @info "Launcher started"

  response = send_local_request(function_test_data.test_argument; local_port = 8080)

  if response != function_test_data.expected_response
    error(
      "During package compilation, responder sent test response $response " *
      "when $(function_test_data.expected_response) was expected"
    )
  else
    @info "Received correct response $response from RIE server"
  end

  # Wait for the precompile statements file to exist
  @info "Waiting for $PRECOMP_STATEMENTS_FNAME to be generated..."
  precomp_timeout = 20.; delay = 0.1
  while true
    isfile(PRECOMP_STATEMENTS_FNAME) && break
    precomp_timeout = precomp_timeout - delay
    if precomp_timeout == 0.
      error("Timed out waiting for $PRECOMP_STATEMENTS_FNAME to generate")
    end
    sleep(delay)
  end
  @info "... $PRECOMP_STATEMENTS_FNAME has been generated"
  println("shutting down launcher")
  kill(launcher_process)
  PRECOMP_STATEMENTS_FNAME
end

function get_script_output_watchers(
    stdout_pipe::Pipe,
    stderr_pipe::Pipe,
    launched_event::Base.Event,
  )::Tuple{Task, Task}
  stdout_watcher = @async begin
    while true
      stdout_text = readline(stdout_pipe)
      @show stdout_text
      if did_launcher_run(stdout_text)
        notify(launched_event)
        break
      end
    end
  end
  @show stdout_watcher
  stderr_watcher = @async begin
    while true
      stderr_text = readline(stderr_pipe)
      @show stderr_text
      if was_port_in_use(stderr_text)
        notify(launched_event)
        break
      end
    end
  end
  @show stderr_watcher
  (stdout_watcher, stderr_watcher)
end

function did_launcher_run(stdout_text::String)::Bool
  occursin("start_runtime", stdout_text)
end

function was_port_in_use(stderr_text::String)::Bool
  occursin("bind: address already in use", stderr_text)
end

function create_jot_sysimage!(
    responder::LocalPackageResponder,
    function_test_data::FunctionTestData,
  )
  run_dir = "jot_temp"
  cd(run_dir) do
    precomp_statements_fname = create_precompile_statements_file!(
      responder, function_test_data
    )
    create_sysimage(
      :Jot,
      precompile_statements_file=precomp_statements_fname,
      sysimage_path="$SYSIMAGE_FNAME",
      cpu_target="x86-64",
    )
  end
  SYSIMAGE_FNAME
end


# function create_sysimage(
#     responder::AbstractResponder,
#     function_test_data::FunctionTestData,
#   )::String
#   precompile_script = get_precompile_jl(responder, function_test_data)
#   mktemp() do path, f
#     create_sysimage(
#       [:Jot,. respo,

#   end


#   open(joinpath(responder.build_dir, "Dockerfile"), "w") do f
#     write(f, dockerfile)
#   end

