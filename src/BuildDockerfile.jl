const runtime_path = "/var/runtime"
const julia_depot_path = "/var/julia_depot"
const jot_github_url = "https://github.com/harris-chris/Jot.jl#master"

function dockerfile_add_julia_image(config::Config)::String
  """
  FROM julia:$(config.image.julia_version)
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

function dockerfile_runtime_files(config::Config, package::Bool)::String
  """
  RUN mkdir -p $(config.image.julia_depot_path)
  ENV JULIA_DEPOT_PATH=$(config.image.julia_depot_path)
  COPY .$(config.image.julia_depot_path)/. $(config.image.julia_depot_path)

  RUN mkdir -p $(config.image.runtime_path)
  WORKDIR $(config.image.runtime_path)

  COPY $(config.image.runtime_path)/. ./

  ENV FUNC_PATH="$(joinpath(config.image.runtime_path, "function.jl"))"
  # RUN FUNC_PATH="$(joinpath(pwd(), builtins.function_path))"

  RUN julia build_runtime.jl $(config.image.runtime_path) $package $(get_dependencies_json(config)) $(config.image.julia_cpu_target)

  # RUN find $(config.image.julia_depot_path)/packages -name "function.jl" -exec cp ./function.jl {} \\;

  ENV PATH="$(config.image.runtime_path):\${PATH}"

  ENTRYPOINT ["$(config.image.runtime_path)/bootstrap"]
  """
end

function dockerfile_add_bootstrap()::String
  bootstrap_script = raw"""
  #!/bin/bash
  if [ -z "${AWS_LAMBDA_RUNTIME_API}" ]; then
    LOCAL="127.0.0.1:9001"
    echo "AWS_LAMBDA_RUNTIME_API not found, starting AWS RIE on $LOCAL"
    exec aws-lambda-rie /usr/local/julia/bin/julia -e "using JuliaLambdaRuntime; start_runtime(\"$LOCAL\")"
  else
    echo "AWS_LAMBDA_RUNTIME_API = $AWS_LAMBDA_RUNTIME_API, running Julia"
    exec /usr/local/julia/bin/julia -e "using JuliaLambdaRuntime; start_runtime(\"$AWS_LAMBDA_RUNTIME_API\")"
  fi
  """

  bootstrap_script_by_line = reduce(*, l * " /" for l in eachline(IOBuffer(bootstrap_script)))

  docker_entry = """
  RUN echo '$bootstrap_script_by_line' > bootstrap
  """

  @show docker_entry
end

function dockerfile_add_permissions(config::Config)::String
  """
  # RUN chmod 644 \$(find $(config.image.runtime_path) -type f)
  # RUN chmod 644 \$(find $(config.image.julia_depot_path) -type f)
  RUN chmod +rwx -R $(config.image.runtime_path)
  RUN chmod +rwx -R $(config.image.julia_depot_path)
  """
end

function get_dependencies_json(config::Config)::String
  # all_deps = [builtins.required_packages; config.image.dependencies]
  all_deps = config.image.dependencies
  all_deps_string = ["\"$dep\"" for dep in all_deps]
  json(all_deps)
end

function get_julia_image_dockerfile(def::Definition)::String
  foldl(
    *, [
    dockerfile_add_julia_image(def.config),
    dockerfile_add_utilities(),
    dockerfile_add_runtime_directories(),
    dockerfile_add_module(def.mod),
    dockerfile_add_jot(),
    dockerfile_add_aws_rie(),
    dockerfile_add_bootstrap(),
  ]; init = "")
end


function get_dockerfile_build_cmd(dockerfile::String, config::Config, no_cache::Bool)::Cmd
  `docker build 
  --rm$(no_cache ? " --no-cache" : "")
  --tag $(get_image_uri_string(config))
  .
  `
end

