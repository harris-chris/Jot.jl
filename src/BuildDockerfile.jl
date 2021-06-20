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

function dockerfile_add_target_package(package_name::String)::String
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

function dockerfile_add_precompile(package_compile::Bool=false)::String
  precompile_script = get_precompile_julia_script(package_compile)
end

function dockerfile_add_bootstrap(
    package_name::String, 
    function_name::String,
  )::String
  """
  ENV PKG_NAME=$(package_name)
  ENV FUNC_FULL_NAME=$package_name.$function_name
  COPY ./precompile.jl ./
  COPY ./bootstrap ./
  RUN julia precompile.jl
  RUN chmod 775 . -R
  ENTRYPOINT ["/var/runtime/bootstrap"]
  """
end

function dockerfile_add_labels(labels::Dict{String, String})::String
  labels = join(["$k=$v" for (k, v) in labels], " ")
  """
  LABEL $labels
  """
end

function get_dockerfile(
    add_responder_script::String,
    labels::Dict{String, String},
    julia_base_version::String,
    responder_package_name::String,
    responder_function_name::String,
  )::String
  foldl(
    *, [
    dockerfile_add_julia_image(julia_base_version),
    dockerfile_add_utilities(),
    dockerfile_add_runtime_directories(),
    add_responder_script,
    dockerfile_add_labels(labels),
    dockerfile_add_jot(),
    dockerfile_add_aws_rie(),
    dockerfile_add_bootstrap(responder_package_name, responder_function_name),
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

