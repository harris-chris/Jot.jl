using Jot

all_lambda_functions = get_all_lambda_functions()
for lambda_function in all_lambda_functions
  @info "Deleting lambda function $(lambda_function.FunctionName)"
  delete!(lambda_function)
end

all_remote_images = get_all_remote_images()
for remote_image in all_remote_images
  @info "Deleting remote image $(remote_image.imageTag)"
  delete!(remote_image)
end

all_local_images = get_all_local_images()
for local_image in all_local_images
  @info "Deleting local image $(local_image.Tag)"
  delete!(local_image)
end
