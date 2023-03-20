# Function Performance

### Naive vs Precompiled vs PackageCompiled
Depending on how the `create_local_image` function is called, the resulting lambda function will be in one of three possible states:
- If you have called `create_local_image` without either the `function_test_data` or `package_compile` parameters, your function will have been neither precompiled nor PackageCopmiled. Of the three states, this is the slowest, with invocations of the function taking the maximum possible time. This is fine for testing but not for production use.
- If you have called `create_local_image` with `function_test_data`, but not `package_compile`, your function will be precompiled, but not PackageCompiled. Precompilation is a Julia-native concept, and it means that any compilation required by the function has been done in advance, and stored as part of the docker image.
- If you have called `create_local_image` with `function_test_data` and with `package_compile=true`, your function will be both precompiled, and PackageCompiled. PackageCompiled means that [PackageCompiler.jl](https://github.com/JuliaLang/PackageCompiler.jl) has been used to create a Julia [system image](https://docs.julialang.org/en/v1/devdocs/sysimg/), and that this system image is part of the docker image. This will result in very fast Lambda function run times, and is highly recommended for production use.

When setting the `package_compile` option to `true`, you will need to also pass a `FunctionTestData` object to the `function_test_data` parameter of `create_local_image`. This defines a sample argument to pass when testing your lambda function, and the expected response that the lambda function should return when passed that argument.

So if your responder function takes a vector of integers, and increases each element by 1:
```
open("increment_vector.jl", "w") do f
  write(f, "increment_vector(v::Vector{Int}) = map(x -> x + 1, v)")
end
increment_responder = get_responder("./increment_vector.jl", :increment_vector, Vector{Int})
```

... then your `FunctionTestData` might look like this:
```
function_test_data = FunctionTestData([1,2,3], [2,3,4])
```
where `[1,2,3]` is the argument you intend to pass to the responder, and `[2,3,4]` is the response you are expecting.

... and your call to `create_local_image` might look like this:
```
`create_local_image(increment_responder; function_test_data=function_test_data, package_compile=true)`
```

### Hot vs warm vs cold starts
When a lambda function is invoked, it may be in either hot, or warm, or a cold state, and this state determines how quickly the function will execute. AWS makes relatively few statements or guarantees about how this works, but from observation:
- A function that has just been executed will be in its hot state.
- After some time has elapsed without being invoked, the function will go from hot to warm. This amount of time appears to be variable, and anywhere between a few minutes and a few hours. This shift from hot to warm can be observed empirically by the function run-time increasing, but it is not clear what being 'warm' actually means.
- After more time has elapsed, the function will go from warm to cold. In the cold state, the docker container has been stopped, and will be started when the function is next invoked. This further increases the function run-time.

### The first execution is special
In addition to this, the very first execution of a function that has been freshly defined in AWS Lambda appears to be special. It takes longer (and produces more debug output) than any subsequent execution.

