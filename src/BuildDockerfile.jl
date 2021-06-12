const runtime_path = "/var/runtime"
const julia_depot_path = "/var/julia_depot"
const jot_github_url = "https://github.com/harris-chris/Jot.jl#master"

function dockerfile_add_julia_image(julia_base_version::String)::String
  """
  FROM julia:$julia_base_version
  """
end

function dockerfile_add_utilities()::String
  """
  RUN apt-get update && apt-get install -y \\
    gcc
  """
end

function dockerfile_add_runtime_directories()::String
  """
  RUN mkdir -p $runtime_path
  ENV JULIA_DEPOT_PATH=$julia_depot_path
  RUN mkdir -p $runtime_path
  WORKDIR $runtime_path
  """
end


function dockerfile_add_module(mod::Module)::String
  package_name = get_package_name(mod)
  add_module_script = "using Pkg; Pkg.develop(path=\\\"$runtime_path/$package_name\\\")"
  """
  RUN mkdir ./$package_name
  COPY ./$package_name ./$package_name
  RUN julia -e \"$add_module_script\"
  """
end

function dockerfile_add_jot()::String
  """
  RUN julia -e "using Pkg; Pkg.add(url=\\\"$jot_github_url\\\")"
  """
end

function dockerfile_add_aws_rie()::String
  """
  RUN curl -Lo ./aws-lambda-rie \\
  https://github.com/aws/aws-lambda-runtime-interface-emulator/releases/latest/download/aws-lambda-rie
  RUN chmod +x ./aws-lambda-rie
  """
end

function dockerfile_add_bootstrap(rf::ResponseFunction)::String
  docker_entry = """
  ENV PKG_NAME=$(get_package_name(rf.mod))
  ENV FUNC_NAME=$(get_response_function_name(rf))
  COPY ./bootstrap ./
  RUN chmod +x ./bootstrap
  ENTRYPOINT ["/var/runtime/bootstrap"]
  """
end

function get_dockerfile(rf::ResponseFunction, julia_base_version::String)::String
  foldl(
    *, [
    dockerfile_add_julia_image(julia_base_version),
    dockerfile_add_utilities(),
    dockerfile_add_runtime_directories(),
    dockerfile_add_module(rf.mod),
    dockerfile_add_jot(),
    dockerfile_add_aws_rie(),
    dockerfile_add_bootstrap(rf),
  ]; init = "")
end

function get_dockerfile_build_cmd(
    dockerfile::String, 
    image_full_name_plus_tag::String, 
    no_cache::Bool,
  )::Cmd
  options = ["--rm", "--iidfile", "id", "--tag", "$image_full_name_plus_tag"]
  no_cache && push!(options, "--no-cache")
  @show options
  `docker build $options .`
end

