
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
    ["--trace-compile=precompilation_statements.jl"];
    jot_path = jot_path
  )

  bootstrap_all = bootstrap_prefix * bootstrap_body

  fname = "single_run_launcher.jl"
  open(fname, "w") do f
    write(f, bootstrap_all)
  end
  fname
end

function create_jot_sysimage!(
    responder::LocalPackageResponder,
    function_test_data::FunctionTestData,
  )
  run_dir = "jot_temp"

  cd(run_dir) do
    launcher_script = create_jot_single_run_launcher_script!(responder)
    @async run(`sh $launcher_script`)
    sleep(1)
    response = send_local_request(function_test_data.test_argument; local_port = 8080)
    if response != function_test_data.expected_response
      error(
        "During package compilation, responder sent test response $response " *
        "when $(function_test_data.expected_response) was expected"
      )
    end
  end
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

