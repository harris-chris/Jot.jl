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

  fname = "single_run_launcher.jl"
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
  launcher = @async redirect_stdio(stdout="launcher_stdout", stderr="launcher_stderr") do
    run(`sh $launcher_script`)
  end
  sleep(1)
  open("launcher_stderr", "r") do f
    if occursin("bind: address already in use", String(read(f)))
      error(
        "Port 8080 is already in use on host machine; unable to start AWS Lambda RIE"
      )
    end
  end
  @info "... launcher script started"
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
  @async Base.throwto(launcher, InterruptException())

  PRECOMP_STATEMENTS_FNAME
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

