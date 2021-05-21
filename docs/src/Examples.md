# Jot Usage Examples

### To make a simple script into a Lambda function...
... where the script is located at `/path/to/script.jl`, and contains a function called `response_func`, that takes a single argument of type `Dict`; also create an `AWSRole` to run it:
```
ex1_responder = get_responder("/path/to/script.jl", :response_func, Dict)
ex1_local_image = create_local_image("ex1", ex1_responder)
(_, ex1_remote_image) = push_to_ecr!(ex1_local_image)
ex1_aws_role = create_aws_role("ex1_aws_role")
ex1_lambda = create_lambda_function(ex1_remote_image, ex1_aws_role)
```

### To make a script with dependencies into a Lambda function...
... where the script is located at `/path/to/script.jl`, and contains a function called `response_func`, that takes a single argument of type `Dict`. The script uses the `SpecialFunctions.jl` package:
```
ex2_responder = get_responder("/path/to/script.jl", :response_func, Dict)
ex2_local_image = create_local_image("ex2", ex2_responder; dependencies=["SpecialFunctions"])
(_, ex2_remote_image) = push_to_ecr!(ex2_local_image)
ex2_aws_role = create_aws_role("ex2_aws_role")
ex1_lambda = create_lambda_function(ex2_remote_image, ex2_aws_role)
```

### To make a package into a LocalImage, using PackageCompiler to reduce its cold start time...
... where the package root (containing the Project.toml) is `/path/to/project`, and the package contains a function called `response_func`, that takes a single argument of type `Vector{T} where {T <: Number}`:
```
ex3_responder = get_responder("/path/to/project", :response_func, Vector)
ex3_local_image = create_local_image("ex3", ex3_responder; package_compile=true)
```

### To make a package in scope into a Responder...
... where the package contains a function called `response_func`, that takes a single argument of type `Vector{Int64}`:
```
using IntVectorResponder
ex4_responder = get_responder(IntVectorResponder, :response_func, Vector{Int64})
```

### To make a package into a local docker image, and test it...
... where the package root (containing the Project.toml) is `/path/to/project`, and the package contains a function called `response_func`, that takes a single argument of type `String` and appends " Responded" to the end of it:
```
ex5_responder = get_responder("/path/to/project", :response_func, String)
ex5_local_image = create_local_image("ex5", ex5_responder)
run_test(ex5_local_image, "test", "test Responded")
```

### To see if a local docker image has the same function as a remote image...
... where local_image is a local docker image, and remote_image is hosted on AWS ECR; the matches function checks that the underlying code of the local image and the remote image match:
```
matches(local_image, remote_image)
```

