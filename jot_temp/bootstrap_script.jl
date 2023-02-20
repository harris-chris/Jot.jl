#!/bin/bash
if [ -z "${AWS_LAMBDA_RUNTIME_API}" ]; then
  LAMBDA_ENDPOINT="127.0.0.1:9001"
  echo "AWS_LAMBDA_RUNTIME_API not found, starting AWS RIE on $LAMBDA_ENDPOINT ..."
  exec ./aws-lambda-rie julia --trace-compile=precompilation_statements.jl -e "using Pkg; Pkg.develop(path=\"/tmp/nix-shell.57p2sh/jl_9iXE2q/append_string_package\"); using Jot; using append_string_package; start_runtime(\"$LAMBDA_ENDPOINT\", append_string_package.append_string, String)" 2>&1
  echo "... AWS_LAMBDA_RUNTIME_API started"
else
  LAMBDA_ENDPOINT=$AWS_LAMBDA_RUNTIME_API
  echo "LAMBDA_ENDPOINT = $AWS_LAMBDA_RUNTIME_API"
  echo "JOT_OBSERVATION Starting Julia ..."
  exec julia --trace-compile=precompilation_statements.jl -e "using Pkg; Pkg.develop(path=\"/tmp/nix-shell.57p2sh/jl_9iXE2q/append_string_package\"); using Jot; using append_string_package; start_runtime(\"$LAMBDA_ENDPOINT\", append_string_package.append_string, String)" 2>&1
  echo "JOT_OBSERVATION ... Julia started"
fi
