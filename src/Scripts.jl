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

ecr_login = """
aws ecr get-login-password --region $(aws.region) \
  | docker login \
  --username AWS \
  --password-stdin \
  $(aws.account_id).dkr.ecr.$(aws.region).amazonaws.com/$(image.name)
"""

