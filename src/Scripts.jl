bootstrap_script = raw"""
#!/bin/bash
if [ -z "${AWS_LAMBDA_RUNTIME_API}" ]; then
  LOCAL="127.0.0.1:9001"
  echo "AWS_LAMBDA_RUNTIME_API not found, starting AWS RIE on $LOCAL"
  exec ./aws-lambda-rie /usr/local/julia/bin/julia -e "using Jot; using $PKG_NAME; start_runtime(\\\"$LOCAL\\\", $FUNC_NAME)"
else
  echo "AWS_LAMBDA_RUNTIME_API = $AWS_LAMBDA_RUNTIME_API, running Julia"
  exec /usr/local/julia/bin/julia -e "using Jot; using $PKG_NAME; start_runtime(\\\"$AWS_LAMBDA_RUNTIME_API\\\", $FUNC_NAME)"
fi
"""

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

function get_create_ecr_repo_script(image_suffix::String, aws_region::String)::String
  """
  aws ecr create-repository \\
    --repository-name $(image_suffix) \\
    --image-scanning-configuration scanOnPush=true \\
    --region $(aws_region)
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
    memory_size::Int64,
  )::String
  """
  aws lambda create-function \\
    --function-name=$(function_name) \\
    --code ImageUri=$(repo_uri) \\
    --role $(role_arn) \\
    --package-type Image \\
    --timeout=$(timeout) \\
    --memory-size=$(memory_size)
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
