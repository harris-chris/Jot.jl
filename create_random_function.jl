using Jot
using Random

this_random_string = randstring(8) |> lowercase

open("append_string.jl", "w") do f
  write(f, "append_string(s::String) = s * \"$this_random_string\"")
end

responder = get_responder("./append_string.jl", :append_string, String)
local_image = create_local_image(
  responder;
  image_suffix="append-string-$this_random_string",
  package_compile=false,
)
remote_image = push_to_ecr!(local_image)
lf = create_lambda_function(remote_image)

@info "Generated function's name is $(lf.FunctionName)"

