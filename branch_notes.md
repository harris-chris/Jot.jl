you can capture the lambda RequestID by invoking the function with --debug on.
Then get the correct output from the cloudflare log
Have `run_test` return this new LambdaInvocationLog object instead of just the time.
