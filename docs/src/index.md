# Jot.jl

*Streamlines the creation and management of AWS Lambda functions written in Julia*

Amazon Web Services does not provide native support for Julia, so functions must be put into docker containers which implement AWS's [Lambda API](https://docs.aws.amazon.com/lambda/latest/dg/runtimes-api.html), and uploaded to AWS Elastic Container Registry (ECR). Jot aims to abstract these complexities away, allowing both julia packages and scripts to be turned into low-latency Lambda functions.

## Introduction
1\. From the JULIA REPL, create a simple script to use as a lambda function... 
```
open("increment_vector.jl", "w") do f
  write(f, "increment_vector(v::Vector{Int}) = map(x -> x + 1, v)")
end
```
2\. ...and turn it into a `Responder`
```
increment_responder = get_responder("./increment_vector.jl", :increment_vector, Vector{Int})
```

3\. Create a local docker image that will implement the responder
```
local_image = create_local_image(increment_responder; image_suffix="increment-vector")
```

4\. Push this local docker image to AWS ECR
```
remote_image = push_to_ecr!(local_image)
```
 
5\. Create a lambda function from this remote_image... 
```
increment_vector_lambda = create_lambda_function(remote_image)
```

6\. ... and test it to see if it's working OK
```
@test run_test(increment_vector_lambda, [2,3,4], [3,4,5]; check_function_state=true) |> first
```

## Package Features
- Easily create AWS Lambda functions from Julia packages or scripts
- Test and check for at multiple stages
- Allows easy checking for version consistency - eg, is a given Lambda Function using the correct code?
- PackageCompiler.jl may be optionally used to greatly speed up cold start times
- JSON read/write and error handling is handled by Jot - you just write standard Julia 

