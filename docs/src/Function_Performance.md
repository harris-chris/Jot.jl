# Function Performance

### The role of PackageCompiler.jl
Jot uses [PackageCompiler.jl](https://github.com/JuliaLang/PackageCompiler.jl) to optimize the performance of its generated functions. The package compilation process uses the concept of an "exemplar session" to discover which Julia methods need to be compiled. This "exemplar session" will, ideally, call all methods that will be used by the actual docker image, when running on AWS Lambda. With Jot, an exemplar session is created automatically during the `create_local_image` stage. This test run simulates how AWS Lambda will invoke the responder function. There are two variables that affect the contents of this test run, and consequently the ultimate performance of the lambda function:

- If you have called `create_local_image` with the `function_test_data` parameter, then the responder function will be called with the `test_arument` parameter supplied in the `function_test_data`. If `function_test_data` is not passed, then the Jot runtime on the docker image - used for HTTP communication with AWS, and JSON reading/writing - will still be part of the exemplar session, but the responder function will not.
- If your responder is a package with a test suite, and you have called `create_local_image` with `run_tests_during_package_compile=true`, then this test suite will be executed as part of the exemplar session. Since the `test_argument` parameter can only invoke a single code path, having a test suite (which presumably tests multiple code paths) is a more robust way to improve performance.

### Passing function_test_data
If your responder function takes a vector of integers, and increases each element by 1:
```
open("increment_vector.jl", "w") do f
  write(f, "increment_vector(v::Vector{Int}) = map(x -> x + 1, v)")
end
increment_responder = get_responder("./increment_vector.jl", :increment_vector, Vector{Int})
```

... then your `function_test_data` might look like this:
```
function_test_data = FunctionTestData([1,2,3], [2,3,4])
```
where `[1,2,3]` is the argument you intend to pass to the responder, and `[2,3,4]` is the response you are expecting.

... and your call to `create_local_image` might look like this:
```
`create_local_image(increment_responder; function_test_data=function_test_data)`
```

### Hot vs warm vs cold starts
When a lambda function is invoked, it may be in either hot, or warm, or a cold state, and this state determines how quickly the function will execute. AWS makes relatively few statements or guarantees about how this works, but from observation:
- A function that has just been executed will be in its hot state.
- After some time has elapsed without being invoked, the function will go from hot to warm. This amount of time appears to be variable, and anywhere between a few minutes and a few hours. This shift from hot to warm can be observed empirically by the function run-time increasing, but it is not clear what being 'warm' actually means.
- After more time has elapsed, the function will go from warm to cold. In the cold state, the docker container has been stopped, and will be started when the function is next invoked. This further increases the function run-time.

### The first execution is special
In addition to this, the very first execution of a function that has been freshly defined in AWS Lambda appears to be special. It takes longer (and produces more debug output) than any subsequent execution.

