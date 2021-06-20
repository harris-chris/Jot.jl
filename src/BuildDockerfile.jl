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
  RUN mkdir -p $temp_path
  ENV TMPDIR=$temp_path
  RUN mkdir -p $runtime_path
  WORKDIR $runtime_path
  """
end

function dockerfile_add_target_package(rf::Responder)::String
  if !isnothing(rf.pkg.repo.source)
    if isdir(rf.pkg.repo.source)
      error("Unable to find local directory $(rf.pkg.repo.source)")
    else
      local_path = rf.pkg.repo.source
      docker_dir_name = isnothing(rf.pkg.name) ? get_package_name(local_path) : rf.pkg.name
      add_module_script = "using Pkg; Pkg.develop(path=\\\"$runtime_path/$docker_dir_name\\\")"
      """
      RUN mkdir ./$docker_dir_name
      COPY ./$local_path ./$docker_dir_name
      RUN julia -e \"$add_module_script\"
      """
    end
  else
    error("Unable to find definition of target package")
  end
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

function dockerfile_add_precompile(package_compile::Bool=false)::String
  precompile_script = get_precompile_julia_script(package_compile)
end

function dockerfile_add_bootstrap(rf::Responder)::String
  """
  ENV PKG_NAME=$(get_package_name(rf.mod))
  ENV FUNC_NAME=$(get_response_function_name(rf))
  COPY ./precompile.jl ./
  COPY ./bootstrap ./
  RUN julia precompile.jl
  RUN chmod 775 . -R
  ENTRYPOINT ["/var/runtime/bootstrap"]
  """
end

function dockerfile_add_response_function_labels(rf::Responder)::String
  labels = Dict(String(name) => rf.name for name in fieldnames(rf) if !ismissing(rf.name))
  dockerfile_add_labels(labels)
end

function dockerfile_add_labels(labels::Dict{String, String})::String
  labels = join(["$k=$v" for (k, v) in labels], " ")
  """
  LABEL $labels
  """
end

function get_dockerfile(
    rf::Responder, 
    julia_base_version::String;
    labels::Dict{String, String},
  )::String
  foldl(
    *, [
    dockerfile_add_julia_image(julia_base_version),
    dockerfile_add_utilities(),
    dockerfile_add_runtime_directories(),
    dockerfile_add_module(rf.mod),
    dockerfile_add_jot(),
    dockerfile_add_aws_rie(),
    dockerfile_add_response_function_labels(rf),
    dockerfile_add_bootstrap(rf),
    isnothing(labels) ? "" : dockerfile_add_labels(labels),
  ]; init = "")
end

function get_dockerfile_build_cmd(
    dockerfile::String, 
    image_full_name_plus_tag::String, 
    no_cache::Bool,
  )::Cmd
  options = ["--rm", "--iidfile", "id", "--tag", "$image_full_name_plus_tag"]
  no_cache && push!(options, "--no-cache")
  `docker build $options .`
end

