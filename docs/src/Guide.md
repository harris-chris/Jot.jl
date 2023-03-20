# Guide

## Installation
From the Julia REPL, type `]` to enter the Pkg REPL mode, then
```
Pkg.add(url="https://github.com/harris-chris/Jot.jl#main")
```

## Background
Julia is not a natively supported language on AWS Lambda. However, a given Julia function can still be used on AWS Lambda by building it into a Docker container, then have that container implement AWS's [Lambda API](https://docs.aws.amazon.com/lambda/latest/dg/runtimes-api.html).

Jot uses a four-step process to go from a given block of Julia code, to a working AWS Lambda function. Each step of this process is represented by a different `type` in Jot. These types are handles for real-life resources, whether on the local filesystem or on AWS:

`Responder` -> `LocalImage` -> `RemoteImage` -> `LambdaFunction`

A `Responder` is our chosen code for responding to Lambda Function calls. It can be as simple as a single function in a short Julia script, or it can be a fully-developed package with multiple dependencies.

A `LocalImage` is a locally-hosted docker image that has Julia installed. In the process of creating a `LocalImage`, the code specified by the `Responder` will be added to it and enabled for use. A `LocalImage` is unique by both - in Docker terminology - its *Repository* (basic identity) and its *Tag* (version). Therefore different versions/*tags* of the same basic image will be represented by different `LocalImage`s. As well as the code specified by the `Responder`, a given `LocalImage` will also have the `Jot.jl` package itself installed. `Jot.jl` hosts the `Responder`, handling HTTP routing and JSON conversion. Additionally, the `LocalImage` has *AWS RIE* installed, a utility provided by AWS that emulates the Lambda run-time environment and so enables local testing of the function.

A `RemoteImage` represents a `LocalImage`, after it has been uploaded to [AWS ECR](https://aws.amazon.com/ecr/). All `RemoteImage`s must be stored in an ECR Repo. This repo maps to the image *Repository*. A repo may therefore contain multiple versions/*tags* for the same *Repository*; therefore multiple `RemoteImage`s that share a *Repository* may be stored in the same ECR Repo.

A `LambdaFunction` is the final stage in the process and represents a working Lambda function, powered by a single `RemoteImage`.

## Best practices

### Using PackageCompiler.jl
[PackageCompiler.jl](https://github.com/JuliaLang/PackageCompiler.jl) is a Julia package that pre-compiles methods. This can be done during the image creation process, and the `create_local_image` function has a `package_compile` option (default `false`) to indicate whether this should be used. Setting `package_compile` to `true` is **highly recommended** for production use; it eliminates almost all of the usual delay while Julia starts up, and so reduces Lambda Function [cold start-up times](https://aws.amazon.com/blogs/compute/operating-lambda-performance-optimization-part-1/) by around 75%, making it competitive with any other language used for AWS Lambda. See [function performance](Function_Performance.md) for more details.

### Working around the one-function-per-container limit
The Lambda API limits you to one function per container. In practice, dividing up all your functions into different containers is not practical. Instead, have the responding function expect a Dict, then use one of the fields of the dict to indicate the function that should be called. The responding function can then just forward the other parameters to the appropriate function.

So instead of creating one responder to do addition:

`function add_response_function(a::Number, b::Number) a + b end`

and another to do subtraction:

`function subtract_response_function(a::Number, b::Number) a - b end`

and having these as separate images, instead create a single responding function:
```
function arithmetic_response(f::String, a::Number, b::Number)
    if f == "add" a + b
    elseif f == "subtract" a - b
    else error("Unable to recognize desired function")
    end
end
```
