using Jot
using Random
include("./performance_test_script_setup.jl")

this_random_string = randstring(8) |> lowercase

open("append_string.jl", "w") do f
  write(f, "append_string(s::String) = s * \"-$this_random_string\"")
end

responder = get_responder("./append_string.jl", :append_string, String)
function_test_data = FunctionTestData("test-", "test-$this_random_string")
local_image = create_local_image(
  responder;
  image_suffix="append-string-$this_random_string",
  function_test_data=function_test_data,
)
remote_image = push_to_ecr!(local_image)
lf = create_lambda_function(remote_image)

@info "Generated function's name is $(lf.FunctionName)"

test_log = get_lambda_function_test_log(
  lf, "test", "test-$this_random_string"
)

@info "Number of precompiles: $(count_precompile_statements(test_log))"
@info "Total run time: $(get_invocation_run_time(test_log))"


