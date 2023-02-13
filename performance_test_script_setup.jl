function setup_images_and_functions(
  )::Tuple{LocalImage, LambdaFunction, LocalImage, LambdaFunction}
  name_prefix = "increment-vector"
  uncompiled_image = get_or_create_local_image(name_prefix, false)
  uncompiled_lambda = get_or_create_lambda_function(name_prefix, false)
  compiled_image = get_or_create_local_image(name_prefix, true)
  compiled_lambda = get_or_create_lambda_function(name_prefix, true)
  (uncompiled_image, uncompiled_lambda, compiled_image, compiled_lambda)
end

function get_or_create_local_image(name_prefix::String, compile::Bool)::LocalImage
  name_suffix = compile ? "compiled" : "uncompiled"
  image_opt = get_local_image("$name_prefix-$name_suffix")
  open("increment_vector.jl", "w") do f
    write(f, "increment_vector(v::Vector{Int}) = map(x -> x + 1, v)")
  end
  increment_responder = get_responder("./increment_vector.jl", :increment_vector, Vector{Int})
  if isnothing(image_opt)
    create_local_image(
      increment_responder;
      image_suffix="$name_prefix-$name_suffix",
      package_compile=compile,
    )
  else
    image_opt
  end
end

function get_or_create_lambda_function(name_prefix::String, compile::Bool)::LambdaFunction
  name_suffix = compile ? "compiled" : "uncompiled"
  lambda_opt = get_lambda_function("$name_prefix-$name_suffix")
  if isnothing(lambda_opt)
    local_image = get_or_create_local_image(compile)
    remote_image = push_to_ecr!(local_image)
    create_lambda_function(remote_image)
  else
    lambda_opt
  end
end
