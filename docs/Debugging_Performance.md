# Debugging and Performance

### About AWS Lambda
Behind-the-scenes, AWS Lambda uses a heavily optimized system for running Lambda functions (some details [here](https://www.amazon.science/blog/how-awss-firecracker-virtual-machines-work)). The process is somewhat opaque and AWS makes few guarantees about exactly how your function will run. If things are not working as expected, either in terms of speed or functionality, it can be useful to add some `println` statements (or other stdout output) to your function, which will then be captured by AWS and can be recovered by Jot.

The `invoke_function_with_log` function runs a Lambda function and returns a tuple of the function result, and a `LambdaFunctionInvocationLog` object that provides
