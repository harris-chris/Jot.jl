using Sockets

const SYSIMAGE_NAME = "CompiledSysImage.so"

function nest_quotes(original::AbstractString)::String
  replace(original, "\"" => "\\\"")
end

function get_bootstrap_script(
    responder::Responder,
    julia_args::Vector{<:AbstractString};
    timeout::Union{Nothing, Int64} = nothing,
  )::String

  bootstrap_shebang = """
  #!/bin/bash
  echo "$BOOTSTRAP_STARTED_JOT_OBSERVATION"
  echo "JULIA_DEPOT_PATH is \$JULIA_DEPOT_PATH"
  echo "\$(ls \$JULIA_DEPOT_PATH)"
  """

  response_function_name = String(responder.response_function)
  response_param_type = responder.response_function_param_type
  responder_package_name = get_package_name(responder)

  julia_start_runtime_command =
    "start_runtime(" *
    join([
      "\\\"\$LAMBDA_ENDPOINT\\\"",
      "$responder_package_name.$response_function_name",
      "$response_param_type",
    ], ", ") *
    ")"

  julia_exec_statements = [
    "using Jot",
    "using $responder_package_name",
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

  bootstrap_body = """
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

  bootstrap_script = bootstrap_shebang * bootstrap_body
  @debug bootstrap_script
  bootstrap_script
end

function get_create_julia_environment_bash_script(
    registry_urls::Vector{<:AbstractString},
  )::String
  create_env_julia_script = get_create_julia_environment_script(registry_urls)
  this_script = replace(create_env_julia_script, "\n" => "; ", "\"" => "\\\"")
  """
  JULIA_DEPOT_PATH=$julia_depot_dir_name julia -e \"$this_script\"
  """
end

function get_create_julia_environment_script(
    registry_urls::Vector{<:AbstractString},
  )::String
  registries_str = if length(registry_urls) > 0
    incl_general = vcat(registry_urls, "https://github.com/JuliaRegistries/General")
    registries_str = foldl(incl_general; init="") do acc, registry
      acc * "Pkg.Registry.add(RegistrySpec(url=\"$registry\"))\n"
    end
  else
    ""
  end
  """
  using Pkg
  Pkg.activate(\"./\")
  $registries_str
  Pkg.instantiate()
  """
end

function get_add_julia_packages_bash_script(
    responder_basename::AbstractString,
    jot_basename::AbstractString,
  )::String
  add_packages_julia_script = get_add_packages_julia_script(
    responder_basename, jot_basename
  )
  this_script = replace(add_packages_julia_script, "\n" => "; ", "\"" => "\\\"")
  """
  JULIA_DEPOT_PATH=$julia_depot_dir_name julia -e \"$this_script\"
  """
end

function get_add_packages_julia_script(
    responder_basename::AbstractString,
    jot_basename::AbstractString,
  )::String
  """
  using Pkg
  Pkg.activate(\"./\")
  Pkg.develop(PackageSpec(path=\"./$jot_basename\"))
  Pkg.develop(PackageSpec(path=\"./$responder_basename\"))
  Pkg.instantiate()
  """
end

function get_invoke_package_compile_script(
    responder::Responder,
  )::String
  """
  using Jot
  using $(get_package_name(responder))
  create_sysimage(
    [:Jot, :$(get_package_name(responder))],
    precompile_statements_file=\"$precompile_statements_fname\",
    sysimage_path=\"$SYSIMAGE_FNAME\",
    cpu_target=\"x86-64\",
  )
  """
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
