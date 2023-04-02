# Jot Usage Examples

### To make a simple script into a Lambda function...
... where the script is located at `/path/to/script.jl`, and contains a function called `response_func`, that takes a single argument of type `Dict`:
```
ex1_responder = get_responder("/path/to/script.jl", :response_func, Dict)
ex1_local_image = create_local_image("ex1", ex1_responder)
ex1_remote_image = push_to_ecr!(ex1_local_image)
ex1_lambda = create_lambda_function(ex1_remote_image)
```

### To make a script with dependencies into a Lambda function...
... where the script is located at `/path/to/script.jl`, and contains a function called `response_func`, that takes a single argument of type `Dict`. The script uses the `SpecialFunctions.jl` package:
```
ex2_responder = get_responder("/path/to/script.jl", :response_func, Dict; dependencies=["SpecialFunctions"])
ex2_local_image = create_local_image("ex2", ex2_responder)
ex2_remote_image = push_to_ecr!(ex2_local_image)
ex2_lambda = create_lambda_function(ex2_remote_image)
```

### To make a package into a local docker image, and test it...
... where the package root (containing the Project.toml) is `/path/to/project`, and the package contains a function called `response_func`, that takes a single argument of type `String` and appends " Responded" to the end of it:
```
ex3_responder = get_responder("/path/to/project", :response_func, String)
test_data = FunctionTestData("test", "test Responded")
ex3_local_image = create_local_image("ex3", ex3_responder; function_test_data=test_data)
run_local_image_test(ex3_local_image, test_data)
```

### To make a package on github into a responder...
... where the package url is `https://github.com/harris-chris/JotTest3/blob/main/Project.toml`, and the package contains a function called `response_func`, that takes a single argument of type `Vector{T} where {T <: Number}`:
```
ex4_responder = get_responder("https://github.com/harris-chris/JotTest3/blob/main/Project.toml", :response_func, Vector)
ex4_local_image = create_local_image("ex4", ex4_responder)
```

### To make a package in scope into a Responder...
... where the package contains a function called `response_func`, that takes a single argument of type `Vector{Int64}`:
```
using IntVectorResponder
ex5_responder = get_responder(IntVectorResponder, :response_func, Vector{Int64})
```

### To see if a local docker image has the same function as a remote image...
... where local_image is a local docker image, and remote_image is hosted on AWS ECR; the matches function checks that the underlying code of the local image and the remote image match:
```
matches(local_image, remote_image)
```

