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
  aws ecr create-repository \
    --repository-name $(image_suffix) \
    --image-scanning-configuration scanOnPush=true \
    --region $(aws_region)
  """
end

function get_delete_ecr_repo_script(image_suffix)::String
  """
  aws ecr delete-repository \
    --force \
    --repository-name $(image_suffix)
  """
end

