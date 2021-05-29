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
    # dockerfile_runtime_files(config, package),
    # dockerfile_add_permissions(config),
  ]; init = "")
end

function get_dockerfile_build_cmd(dockerfile::String, config::Config, no_cache::Bool)::Cmd
  `
  docker build - 
  `
end

function ttt()
  `
  docker build \\
    --rm $(no_cache ? "--no-cache" : "") \\
    --tag $(get_image_uri_string(config)) \\
    - \<\<EOF 
    $dockerfile 
    EOF
  `
end

function get_dockerfile_build_script(config::Config, no_cache::Bool)::String
  contents = """
  #!/bin/bash
  DIR="\$( cd "\$( dirname "\${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
  docker build \\
    --rm $(no_cache ? "--no-cache" : "") \\
    --tag $(get_image_uri_string(config)) \\
    \$DIR/.
  """
end
