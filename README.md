# Jot

#### Jot streamlines the creation and management of AWS Lambda functions written in Julia. 

Amazon Web Services does not provide native support for Julia, so functions must be put into docker containers which implement AWS's [Lambda API](https://docs.aws.amazon.com/lambda/latest/dg/runtimes-api.html), and uploaded to AWS Elastic Container Registry (ECR). Jot aims to reduce this to a simple, customizable and transparent process, which results in a low-latency Lambda function:

1\. Create a simple script to use as a lambda function and turn it into a `Responder`
```
write(
    "./add_one_script.jl", 
    "increment_vector(v::Vector{Int}) = map(x -> x + 1, v)"
) 
increment_responder = Responder("./add_one_script.jl", :increment_vector, Vector{Int})
```

2\. Create a local docker image that will implement the responder
```
local_image = create_local_image("increment-vector", increment_responder)
```

3\. Push this local docker image to AWS ECR; create an AWS role that can execute it
```
(ecr_repo, remote_image) = push_to_ecr!(local_image)
aws_role = create_aws_role("increment-vector-role")
```
 
4\. Create a lambda function from this remote_image... 
```
increment_vector_lambda = create_lambda_function(remote_image, aws_role)
```

5\. ... and test it to see if it's working OK
```
run_test(increment_vector_lambda, function_argument=[2,3,4], expected_result=[3,4,5])
```
