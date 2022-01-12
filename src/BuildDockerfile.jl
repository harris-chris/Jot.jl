const runtime_path = "/var/runtime"
const julia_depot_path = "/var/runtime/julia_depot"
const temp_path = "/tmp"
const jot_github_url = "https://github.com/harris-chris/Jot.jl#main"

function dockerfile_add_julia_image(julia_base_version::String)::String
  """
  FROM julia:$julia_base_version
  """
end

function dockerfile_add_additional_registries(additional_registries::Vector{String})::String
  using_pkg_script = "using Pkg; "
  add_registries_script = begin
    str = ""
    for reg in additional_registries
      str *= "Pkg.Registry.add(RegistrySpec(url = \\\"$(reg)\\\")); "
    end
    str *= "Pkg.Registry.add(\\\"General\\\")"
    str == "" ? str : str * "; "
  end
  """
  RUN julia -e \"$using_pkg_script$add_registries_script\"
  """
end

function dockerfile_add_utilities()::String
  """
  RUN apt-get update && apt-get install -y \\
    build-essential
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

function dockerfile_copy_build_dir()::String
  """
  COPY . .
  """
end

function dockerfile_add_responder(res::LocalPackageResponder)::String
  using_pkg_script = "using Pkg; "
  add_module_script = "Pkg.develop(path=\\\"$runtime_path/$(res.package_name)\\\"); "
  instantiate_script = "Pkg.instantiate(); "
  """
  RUN julia -e \"$using_pkg_script$add_module_script$instantiate_script\"
  """
end

function dockerfile_add_jot()::String
  test_running = get(ENV, "JOT_TEST_RUNNING", nothing)
  jot_url = if isnothing(test_running) || test_running == "false"
    jot_github_url
  else
    this_branch = readchomp(`git branch --show-current`)
    jot_github_url * "#$this_branch"
  end
  @debug jot_url

  """
  RUN julia -e "using Pkg; Pkg.add([\\\"HTTP\\\", \\\"JSON3\\\"]); Pkg.add(url=\\\"$jot_url\\\")"
  """
end

function dockerfile_add_aws_rie()::String
  """
  RUN curl -Lo ./aws-lambda-rie \\
  https://github.com/aws/aws-lambda-runtime-interface-emulator/releases/latest/download/aws-lambda-rie
  RUN chmod +x ./aws-lambda-rie
  """
end

function dockerfile_add_bootstrap(
    package_name::String,
    function_name::String,
    ::Type{IT}
  )::String where {IT}
  """
  ENV PKG_NAME=$(package_name)
  ENV FUNC_FULL_NAME=$package_name.$function_name
  ENV FUNC_PARAM_TYPE=$IT
  RUN chmod 775 . -R
  ENTRYPOINT ["/var/runtime/bootstrap"]
  """
end

function dockerfile_add_precompile(package_compile::Bool)::String
  run_init = """
  RUN julia init.jl
  """
end


function dockerfile_add_labels(labels::Labels)::String
  labels_str = to_docker_buildfile_format(labels)
  """
  LABEL $labels_str
  """
end

function get_dockerfile_build_cmd(
    dockerfile::String,
    image_full_name_plus_tag::String,
    no_cache::Bool,
    build_args::Vector{Pair}
  )::Cmd
  options = ["--rm", "--iidfile", "id", "--tag", "$image_full_name_plus_tag"]
  [push!(options, e) for e in map(x -> [first(x), last(x)], build_args) |> x -> reduce(vcat, x)]
  no_cache && push!(options, "--no-cache")
  `docker build $options .`
end

