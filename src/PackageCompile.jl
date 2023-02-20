
struct FunctionTestData
  test_argument::Any
  expected_response::Any
end


function get_precompile_statements_script(
    responder::LocalPackageResponder
  )
  jot_path = abspath(pwd())
  this_dir = "jot_temp"

  cd(this_dir) do
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

    open("bootstrap_script.jl", "w") do f
      write(f, bootstrap_all)
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

