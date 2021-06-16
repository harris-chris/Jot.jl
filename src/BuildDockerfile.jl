const runtime_path = "/var/runtime"
const julia_depot_path = "/var/runtime/julia_depot"
const temp_path = "/tmp"
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
  RUN mkdir -p $julia_depot_path
  ENV JULIA_DEPOT_PATH=$julia_depot_path
  RUN chmod 777 -R $runtime_path
  RUN mkdir -p $temp_path
  ENV TMPDIR=$temp_path
  RUN chmod 777 -R $runtime_path
  RUN mkdir -p $runtime_path
  WORKDIR $runtime_path
  RUN chmod 777 -R $runtime_path
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

function dockerfile_add_precompile(package_compiler::Bool=false)::String
  precompile_script = get_precompile_julia_script(package_compiler)
end

if package == "true"
  create_sysimage(
                  :JuliaLambdaRuntime, 
                  precompile_execution_file=precompile_file,
                  replace_default=true,
                  cpu_target=cpu_target,
                 )
end

function dockerfile_add_bootstrap(rf::ResponseFunction)::String
  """
  ENV PKG_NAME=$(get_package_name(rf.mod))
  ENV FUNC_NAME=$(get_response_function_name(rf))
  COPY ./precompile.jl ./
  COPY ./bootstrap ./
  RUN julia precompile.jl
  ENTRYPOINT ["/var/runtime/bootstrap"]
  RUN chmod 777 -R $runtime_path
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

