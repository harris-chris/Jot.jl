using Sockets

const SYSIMAGE_NAME = "CompiledSysImage.so"

function nest_quotes(original::AbstractString)::String
  replace(original, "\"" => "\\\"")
end

function get_bootstrap_script(
    responder::LocalPackageResponder,
    julia_depot_path::AbstractString,
    temp_path::AbstractString,
    julia_args::Vector{<:AbstractString},
  )::String

  bootstrap_shebang = """
  #!/bin/bash
  echo "$BOOTSTRAP_STARTED_JOT_OBSERVATION"
  """

  bootstrap_env_vars = """
  export JULIA_DEPOT_PATH=$temp_path:$julia_depot_path
  """

  bootstrap_body = get_bootstrap_body(responder, julia_args)
  bootstrap_script = bootstrap_shebang * bootstrap_env_vars * bootstrap_body
  @debug bootstrap_script
  bootstrap_script
end

function get_create_julia_environment_script(
    responder_package_path::AbstractString,
    create_dir::AbstractString;
    jot_branch::AbstractString = "main",
  )::String
  """
  using Pkg
  cd(\"$create_dir\") do
    Pkg.activate(\".\")
    Pkg.add(url=\"$jot_github_url\", rev=\"$jot_branch\")
    Pkg.develop(PackageSpec(path=\"$responder_package_path\"))
    Pkg.precompile()
  end
  """
end

function get_bootstrap_body(
    responder::LocalPackageResponder,
    julia_args::Vector{<:AbstractString};
    timeout::Union{Nothing, Int64} = nothing,
  )::String

  response_function_name = String(responder.response_function)
  response_param_type = responder.response_function_param_type
  responder_package_path = joinpath(responder.build_dir, responder.package_name)

  julia_start_runtime_command =
    "start_runtime(" *
    join([
      "\\\"\$LAMBDA_ENDPOINT\\\"",
      "$(responder.package_name).$response_function_name",
      "$response_param_type",
    ], ", ") *
    ")"

  julia_exec_statements = [
    "using Jot",
    "using $(responder.package_name)",
    julia_start_runtime_command,
  ]
  julia_exec = join(julia_exec_statements, "; ")

  run_julia_rie_cmd =
    "exec " *
    (isnothing(timeout) ? "" : "timeout $(timeout)s ") *
    "./aws-lambda-rie julia " *
    join(julia_args, " ") *
    " -e \"$julia_exec\""

  run_julia_lambda_cmd =
    "exec " *
    (isnothing(timeout) ? "" : "timeout $(timeout)s ") *
    "julia " *
    join(julia_args, " ") *
    " -e \"$julia_exec\""

  """
  if [ -z "\${AWS_LAMBDA_RUNTIME_API}" ]; then
    LAMBDA_ENDPOINT="127.0.0.1:9001"
    echo "AWS_LAMBDA_RUNTIME_API not found, starting AWS RIE on \$LAMBDA_ENDPOINT ..."
    $run_julia_rie_cmd 2>&1
    echo "... AWS_LAMBDA_RUNTIME_API started"
  else
    LAMBDA_ENDPOINT=\$AWS_LAMBDA_RUNTIME_API
    echo "LAMBDA_ENDPOINT = \$AWS_LAMBDA_RUNTIME_API"
    echo "$STARTING_JULIA_JOT_OBSERVATION"
    $run_julia_lambda_cmd 2>&1
    echo "$JULIA_STARTED_JOT_OBSERVATION"
  fi
  """
end

function get_invoke_package_compile_script(
    responder::LocalPackageResponder,
    function_test_data::FunctionTestData,
  )::String
  """
  using Jot
  using $(responder.package_name)
  function_test_data = $function_test_data
  create_sysimage(
    [:Jot, :$(responder.package_name)],
    precompile_statements_file=\"$PRECOMP_STATEMENTS_FNAME\",
    sysimage_path=\"$SYSIMAGE_FNAME\",
    cpu_target=\"x86-64\",
  )
  """
end

function start_lambda_server(host::AbstractString, port::Int64)
  ROUTER = HTTP.Router()
  server = Sockets.listen(Sockets.InetAddr(parse(IPAddr, host), port))

  function get_respond(req::HTTP.Request)
    println("received get request")
    return HTTP.Response(
                         200,
                         ["Lambda-Runtime-Aws-Request-Id" => "dummy-request-id"];
                         body=JSON3.write(3),
                        )
  end

  function post_respond(req::HTTP.Request)
    answer = JSON3.read(IOBuffer(HTTP.payload(req)), Int64)
    println(answer)
    println("Closing server")
    close(server)
    return HTTP.Response(200, JSON3.write(answer))
  end

  HTTP.@register(ROUTER, "POST", "/*", post_respond)
  HTTP.@register(ROUTER, "GET", "/*", get_respond)
  @sync HTTP.serve(ROUTER, host, port, server=server)
end

function start_test_server(host::AbstractString, port::Int64, test_argument::Any)
  ROUTER = HTTP.Router()
  server = Sockets.listen(Sockets.InetAddr(parse(IPAddr, host), port))

  function get_respond(req::HTTP.Request)
    println("received get request")
    return HTTP.Response(
                         200,
                         ["Lambda-Runtime-Aws-Request-Id" => "dummy-request-id"];
                         body=JSON3.write(test_argument),
                        )
  end

  # function post_respond(req::HTTP.Request)
  #   answer = JSON3.read(IOBuffer(HTTP.payload(req)), Int64)
  #   println(answer)
  #   println("Closing server")
  #   close(server)
  #   return HTTP.Response(200, JSON3.write(answer))
  # end

  # HTTP.@register(ROUTER, "POST", "/*", post_respond)
  HTTP.@register(ROUTER, "GET", "/*", get_respond)
  @async HTTP.serve(ROUTER, host, port, server=server)
end

function get_lambda_dummy_server_jl()::String
  """
  using HTTP
  using JSON3

  function get_respond(req::HTTP.Request)
    println("received get request")
    return HTTP.Response(
                         200,
                         ["Lambda-Runtime-Aws-Request-Id" => "dummy-request-id"];
                         body=JSON3.write(3),
                        )
  end

  function post_respond(req::HTTP.Request)
    answer = JSON3.read(IOBuffer(HTTP.payload(req)), Int64)
    println(answer)
    return HTTP.Response(200, JSON3.write(answer))
    exit(86)
  end

  const ROUTER = HTTP.Router()

  HTTP.@register(ROUTER, "POST", "/*", post_respond)
  HTTP.@register(ROUTER, "GET", "/*", get_respond)
  HTTP.serve(ROUTER, "127.0.0.1", 9001)
  """
end

function get_init_script(
    function_test_data::Union{Nothing, FunctionTestData},
    cpu_target::AbstractString,
    julia_depot_path::AbstractString,
  )::String
  precomp = """
  import Pkg
  using Jot
  @info "Running precompile ..."
  Pkg.precompile()
  @info "... finished running precompile"
  """

  package_compile_script = """
  @info "Running package compile script ..."
  Pkg.add(Pkg.PackageSpec(;name="PackageCompiler", version="2.1.2"))
  using PackageCompiler
  # TODO: check intelligently for when it has started
  @async Jot.start_test_server("127.0.0.1", 9001, function_test_data.test_argument)
  sleep(5)
  create_sysimage(
    :Jot,
    precompile_execution_file="precompile.jl",
    sysimage_path="$(julia_depot_path)/$(SYSIMAGE_NAME)",
    cpu_target="$cpu_target",
  )
  sysimage_generated = "$SYSIMAGE_NAME" in readdir("$julia_depot_path")
  if sysimage_generated
    @info "Sysimage generated at $(julia_depot_path)/$(SYSIMAGE_NAME)"
  else
    @info "Sysimage not found at $(julia_depot_path)/$(SYSIMAGE_NAME)"
  end
  @info "... finished running package compile script"
  """
  init_script = if isnothing(function_test_data)
    precomp
  else
    precomp * package_compile_script
  end
  @show init_script
end

function get_precompile_jl(
    responder::AbstractResponder,
    function_test_data::FunctionTestData,
  )::String
  package_name = responder.package_name
  function_name = String(responder.response_function)
  argument_type = responder.response_function_param_type
  test_argument = function_test_data.test_argument
  precompile_jl = """
  using Jot
  using $package_name
  using HTTP
  using Pkg

  try
    Pkg.test("$package_name")
  catch e
    isa(e, LoadError) && rethrow(e)
  end

  @async Jot.start_runtime(
    "127.0.0.1:9001", "$function_name", argument_type; single_shot=true
  )
  sleep(10)
  """
  @debug precompile_jl
  precompile_jl
end

function get_lambda_function_tags_script(lambda_function::LambdaFunction)::String
  """
  aws lambda list-tags --resource $(lambda_function.FunctionArn)
  """
end

function get_ecr_repo_tags_script(ecr_repo::ECRRepo)::String
  """
  aws ecr list-tags-for-resource --resource-arn=$(ecr_repo.repositoryArn)
  """
end

function get_delete_ecr_repo_tags_script(
    ecr_repo::ECRRepo,
    tag_keys::Vector{<:AbstractString}
  )::String
  """
  aws ecr untag-resource \\
       --resource-arn $(ecr_repo.repositoryArn) \\
       --tag-keys $(join(tag_keys, " "))
  """
end

function get_images_in_ecr_repo_script(ecr_repo::ECRRepo)::String
  """
  aws ecr list-images --repository-name=$(ecr_repo.repositoryName)
  """
end

function get_delete_remote_image_script(remote_image::RemoteImage)::String
  """
  aws ecr batch-delete-image \\
    --repository-name=$(remote_image.ecr_repo.repositoryName) \\
    --image-ids imageDigest=$(remote_image.imageDigest)
  """
end

function get_ecr_login_script(aws_config::AWSConfig, image_suffix::AbstractString)
  image_full_name = get_image_full_name(aws_config, image_suffix)
  """
  aws ecr get-login-password --region $(aws_config.region) \\
    | docker login \\
    --username AWS \\
    --password-stdin \\
    $image_full_name
  """
end

get_docker_push_script(image_full_name_plus_tag::AbstractString) = """
docker push $image_full_name_plus_tag
"""

function get_create_ecr_repo_script(
    image_suffix::AbstractString,
    aws_region::AbstractString,
    labels::Labels
  )::String
  tags_json = to_json(labels)
  """
  aws ecr create-repository \\
    --repository-name $(image_suffix) \\
    --image-scanning-configuration scanOnPush=true \\
    --region $(aws_region) \\
    --tags '$tags_json'
  """
end

function get_delete_ecr_repo_script(repo_name)::String
  """
  aws ecr delete-repository \\
    --force \\
    --repository-name $(repo_name)
  """
end

function get_create_lambda_role_script(role_name)::String
  """
  TRUST_POLICY=\$(cat <<EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Service": "lambda.amazonaws.com"
        },
        "Action": "sts:AssumeRole"
      }
    ]
  }
  EOF
  )

  aws iam create-role \\
    --role-name $(role_name) \\
    --assume-role-policy-document "\$TRUST_POLICY"
  """
end

function get_attach_lambda_execution_policy_to_role_script(
    role_name::AbstractString,
  )::String
  """
  aws iam attach-role-policy --role-name $(role_name) --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
  """
end

function get_list_attached_role_policies_script(role_name::String)::String
  """
  aws iam list-attached-role-policies --role-name $(role_name)
  """
end

function get_detach_role_policy_script(
    role_name::String,
    policy_arn::String,
  )::String
  """
  aws iam detach-role-policy --role-name $(role_name) --policy-arn $(policy_arn)
  """
end

function get_delete_lambda_role_script(role_name)::String
  """
  aws iam delete-role --role-name $(role_name)
  """
end

function get_create_lambda_function_script(
    function_name::String,
    repo_uri::String,
    role_arn::String,
    timeout::Int64,
    memory_size::Int64;
    labels::Labels,
  )::String
  tags_shorthand = to_aws_shorthand(labels)
  """
  aws lambda create-function \\
    --function-name=$(function_name) \\
    --code ImageUri=$(repo_uri) \\
    --role $(role_arn) \\
    --package-type Image \\
    --timeout=$(timeout) \\
    --memory-size=$(memory_size) \\
    --tags $tags_shorthand
  """
end

function get_lambda_function_status(
    function_name::String,
  )::String
  """
  aws lambda get-function-configuration --function-name $function_name
  """
end

function get_delete_lambda_function_script(function_arn::String)::String
  """
  aws lambda delete-function \\
    --function-name=$(function_arn)
  """
end

function get_invoke_lambda_function_script(
    function_arn::String,
    request::String,
    outfile::String,
    debug::Bool,
  )::String

  """
  aws lambda invoke \\
    --function-name=$(function_arn) \\
    --payload='$(request)' \\
    --cli-binary-format raw-in-base64-out \\
    $(if debug "--debug" else "" end) $outfile
  """
end

function get_describe_log_groups_script()::String
   """
   aws logs describe-log-groups
   """
end

function get_log_streams_script(log_group_name::String)::String
   """
   aws logs describe-log-streams \\
       --log-group-name '$log_group_name' \\
       --order-by LastEventTime \\
       --descending
   """
end

function get_log_events_script(
    log_group_name::AbstractString,
    log_stream_name::AbstractString,
  )::String
  """
  aws logs get-log-events \\
      --log-group-name '$log_group_name' \\
      --log-stream-name '$log_stream_name'
  """
end
