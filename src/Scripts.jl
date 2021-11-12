using Sockets

bootstrap_script = raw"""
#!/bin/bash
if [ -z "${AWS_LAMBDA_RUNTIME_API}" ]; then
  LOCAL="127.0.0.1:9001"
  echo "AWS_LAMBDA_RUNTIME_API not found, starting AWS RIE on $LOCAL"
  exec ./aws-lambda-rie /usr/local/julia/bin/julia -e "using Jot; using $PKG_NAME; start_runtime(\\\"$LOCAL\\\", $FUNC_FULL_NAME, $FUNC_PARAM_TYPE)"
else
  echo "AWS_LAMBDA_RUNTIME_API = $AWS_LAMBDA_RUNTIME_API, running Julia"
  # touch /tmp/working
  # echo "CREATED TEMPORARY FILE"
  # exec /usr/local/julia/bin/julia -e "using Jot; println(pwd())"
  # echo "JULIA CREATED TEMP"
  exec /usr/local/julia/bin/julia -e "using Jot; using $PKG_NAME; start_runtime(\\\"$AWS_LAMBDA_RUNTIME_API\\\", $FUNC_FULL_NAME, $FUNC_PARAM_TYPE)"
fi
"""

function start_lambda_server(host::String, port::Int64)
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
    package_compile::Bool,
    cpu_target::String,
  )::String
  precomp = """
  import Pkg
  using Jot
  Pkg.precompile()
  """
  pc_script = """
  Pkg.add(Pkg.PackageSpec(;name="PackageCompiler", version="1.7.7"))
  using PackageCompiler
  @async Jot.start_lambda_server("127.0.0.1", 9001) 
  create_sysimage(
                  :Jot, 
                  precompile_execution_file="precompile.jl",
                  replace_default=true,
                  cpu_target="$cpu_target",
                 )
  """
  package_compile ? precomp * pc_script : precomp
end

function get_precompile_jl(
    package_name::String,
  )::String
  """
  using Jot
  using $package_name
  using Pkg

  Pkg.test("$package_name")

  rf(i::Int64) = i + 1

  Jot.start_runtime("127.0.0.1:9001", rf, Int64; single_shot=true)
  """
end

function get_lambda_function_tags_script(lambda_function::LambdaFunction)::String
  """
  aws lambda list-tags --resource $(lambda_function.FunctionArn)
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

function get_ecr_login_script(aws_config::AWSConfig, image_suffix::String)
  image_full_name = get_image_full_name(aws_config, image_suffix)
  """
  aws ecr get-login-password --region $(aws_config.region) \\
    | docker login \\
    --username AWS \\
    --password-stdin \\
    $image_full_name
  """
end

get_docker_push_script(image_full_name_plus_tag::String) = """
docker push $image_full_name_plus_tag
"""

function get_create_ecr_repo_script(image_suffix::String, aws_region::String, labels::Labels)::String
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
  )::String
  """
  aws lambda invoke \\
    --function-name=$(function_arn) \\
    --payload='$(request)' \\
    --cli-binary-format raw-in-base64-out \\
    $outfile
  """
end
