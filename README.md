## Jot.jl

*Jot streamlines the creation and management of AWS Lambda functions written in Julia.*

## Installation

Via the `Pkg` API:

```julia
julia> import Pkg; Pkg.add(url="https://github.com/harris-chris/Jot.jl#main")

```
[![][docs-stable-img]][docs-stable-url] [![][docs-dev-img]][docs-dev-url]

Amazon Web Services does not provide native support for Julia, so functions must be put into docker containers which implement AWS's [Lambda API](https://docs.aws.amazon.com/lambda/latest/dg/runtimes-api.html), and uploaded to AWS Elastic Container Registry (ECR). Jot aims to abstract these complexities away, allowing both julia packages and scripts to be turned into low-latency Lambda functions.

More examples can be found in the [examples](https://harris-chris.github.io/Jot.jl/stable/) page, but this can be as simple as:

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

## Documentation

- [**STABLE**][docs-stable-url] &mdash; **documentation of the most recently tagged version.**
- [**DEVEL**][docs-dev-url] &mdash; *documentation of the in-development version.*

## Prerequisites

The package is tested against Julia versions `1.5` and above on Linux. It also requires Docker (tested against version `20`) and the AWS CLI (tested against version `2`).

[docs-stable-img]: https://img.shields.io/badge/docs-stable-blue.svg
[docs-stable-url]: https://harris-chris.github.io/Jot.jl/stable/
[docs-dev-img]: https://img.shields.io/badge/docs-dev-blue.svg
[docs-dev-url]: https://harris-chris.github.io/Jot.jl/dev/

