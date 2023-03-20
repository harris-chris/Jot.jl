# Debugging Functions

### Obtaining Debug Output
Behind-the-scenes, AWS Lambda uses a heavily optimized system for running Lambda functions (some details [here](https://www.amazon.science/blog/how-awss-firecracker-virtual-machines-work)). The process is somewhat opaque and AWS makes few guarantees about exactly how your function will run. If things are not working as expected, either in terms of speed or functionality, it can be useful to add some `println` statements (or other stdout output) to your function, which will then be captured by AWS and can be recovered by Jot.

The `invoke_function_with_log` function runs a Lambda function and returns a tuple of the function result, and a `LambdaFunctionInvocationLog` object that provides some diagnostics on that particular function invocation:
- `show_log_events(log)` will show all output, either by the responder function or by Jot in the course of running the responder function, that was printed to stdout, as well as the time intervals between these outputs.
- `show_observations(log)` will do the same, but will only show stdout output that starts with the text "JOT_OBSERVATION". This allows you to manually narrow down the output you see.
- `get_invocation_time_breakdown(log)` will return a `InvocationTimeBreakdown` object, that splits out the total invocation time (expressed in milliseconds) between function run time, precompile time, and ex-function-run time excl. precompile time.
