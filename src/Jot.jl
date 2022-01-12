module Jot

# IMPORTS
using Base.Filesystem
using Dates
using JSON3
using OrderedCollections
using Parameters
using Pkg
using PrettyTables
using IsURL
using Random
using Setfield
using StructTypes
using TOML
import Base.delete!

# EXPORTS
export AWSConfig, LambdaException
export get_responder, AbstractResponder, LocalPackageResponder
export LocalImage, Container, RemoteImage, ECRRepo, AWSRole, LambdaFunction
export get_aws_role, get_user_labels
export LambdaFunctionState, pending, active
export get_dockerfile, build_definition
export run_image_locally, create_local_image, get_local_image
export send_local_request
export run_test
export stop_container, is_container_running
export create_ecr_repo, get_ecr_repo, push_to_ecr!
export get_remote_image
export create_aws_role
export create_lambda_function, get_lambda_function, invoke_function
export create_lambda_components, with_remote_image!, with_lambda_function!
export delete!
export show_lambdas
export get_labels, get_lambda_name
export get_all_local_images, get_all_remote_images, get_all_ecr_repos, get_all_lambda_functions
export get_all_containers, get_all_aws_roles
export LambdaComponents

# CONSTANTS
const docker_hash_limit = 12

abstract type LambdaComponent end

include("Responder.jl")
include("LocalImage.jl")
include("ECRRepo.jl")
include("RemoteImage.jl")
include("Container.jl")
include("LambdaFunction.jl")
include("AWS.jl")
include("LambdaComponents.jl")
include("Labels.jl")

function get_commit(path::String)::String
  try
    readchomp(`set -euo pipefail bash -c "PWD=pwd; cd $path; git rev-parse HEAD; cd \$PWD"`)
  catch e
    "None"
  end
end

function get_commit(mod::Module)::Union{Missing, String}
  mod_path = get_package_path(mod)
  get_commit(mod_path)
end

function get_package_path(mod::Module)::String
  module_path = Base.moduleroot(mod) |> pathof
  joinpath(splitpath(module_path)[begin:end-2]...)
end

function get_package_name(mod::Module)::String
  splitpath(get_package_path(mod))[end]
end

# -- get_tree_hash --

function get_tree_hash(res::LocalPackageResponder)::String
  get_tree_hash(joinpath(res.build_dir, res.package_name))
end

function get_tree_hash(path::String)::String
  Pkg.GitTools.tree_hash(path) |> bytes2hex
end

function get_tree_hash(i::Union{LocalImage, RemoteImage})::String
  get_labels(i).RESPONDER_TREE_HASH
end

function get_tree_hash(l::LambdaFunction)::String
  get_labels(l).RESPONDER_TREE_HASH
end

function get_tree_hash(lc::LambdaComponents)::String
  if !isnothing(lc.local_image)
    get_tree_hash(lc.local_image)
  elseif !isnothing(lc.remote_image)
    get_tree_hash(lc.remote_image)
  else
    get_tree_hash(lc.lambda_function)
  end
end

function get_image_full_name(
    aws_config::AWSConfig,
    image_suffix::String,
  )::String
  registry = "$(aws_config.account_id).dkr.ecr.$(aws_config.region).amazonaws.com"
  "$registry/$image_suffix"
end

function get_image_full_name_plus_tag(
    aws_config::AWSConfig,
    image_suffix::String,
    image_tag::String,
  )::String
  "$(get_image_full_name(aws_config, image_suffix)):$image_tag"
end

function get_image_full_name_plus_tag(image::LocalImage)::String
  "$(image.Repository):$(image.Tag)"
end

include("BuildDockerfile.jl")
include("Runtime.jl")
include("Scripts.jl")

function get_response_function_name(res::LocalPackageResponder)::String
  "$(res.package_name).$(res.response_function)"
end

function move_local_to_build_directory(build_dir::String, path::String, name::String)
  Base.Filesystem.cp(path, joinpath(build_dir, name))
end

function create_build_directory()::String
  build_dir = mktempdir()
  build_dir
end

function write_to_build_dir(
    content::String,
    build_dir::String,
    filename::String,
  )
  full_fpath = joinpath(build_dir, filename)
  open(full_fpath, "w") do f
    write(f, content)
  end
end

function add_scripts_to_build_dir(
    package_compile::Bool,
    julia_cpu_target::String,
    responder::AbstractResponder,
  )
  add_to_build(content, fname) = write_to_build_dir(content, responder.build_dir, fname)
  bootstrap_script |> x -> add_to_build(x, "bootstrap")
  get_init_script(package_compile, julia_cpu_target) |> x -> add_to_build(x, "init.jl")
  if package_compile
    get_precompile_jl(responder.package_name) |> x -> add_to_build(x, "precompile.jl")
  end
end

"""
    get_dockerfile(
        responder::AbstractResponder,
        julia_base_version::String,
        package_compile::Bool;
        user_defined_labels::AbstractDict{String, String} = AbstractDict{String, String}(),
        dockerfile_update::Function = x -> x,
      )::String

Returns contents for a Dockerfile. This function is called in `create_local_image` in order to
create a local docker image.
"""
function get_dockerfile(
    responder::AbstractResponder,
    julia_base_version::String,
    package_compile::Bool;
    user_defined_labels::AbstractDict{String, String} = AbstractDict{String, String}(),
    dockerfile_update::Function = x -> x,
  )::String
  overlapped_keys = [key for key in user_defined_labels if key in map(String, fieldnames(Labels))]
  if length(overlapped_keys) > 0
    error("User-defined labels $(join(overlapped_keys, ", ")) overlap with Jot-defined labels")
  end
  combined_labels = add_user_defined_labels(get_labels(responder), user_defined_labels)
  generated_dockerfile = foldl(
    *, [
    dockerfile_add_julia_image(julia_base_version),
    dockerfile_add_utilities(),
    dockerfile_add_runtime_directories(),
    dockerfile_add_additional_registries(responder.registry_urls),
    dockerfile_copy_build_dir(),
    dockerfile_add_responder(responder),
    dockerfile_add_labels(combined_labels),
    dockerfile_add_jot(),
    dockerfile_add_aws_rie(),
    dockerfile_add_bootstrap(responder.package_name,
                             String(responder.response_function),
                             responder.response_function_param_type),
    dockerfile_add_precompile(package_compile),
  ]; init = "")
  dockerfile_update(generated_dockerfile)
end

"""
    create_local_image(
        responder::AbstractResponder;
        image_suffix::Union{Nothing, String} = nothing,
        aws_config::Union{Nothing, AWSConfig} = nothing,
        image_tag::String = "latest",
        no_cache::Bool = false,
        julia_base_version::String = "1.6.1",
        julia_cpu_target::String = "x86-64",
        package_compile::Bool = false,
        user_defined_labels::AbstractDict{String, String} = OrderedDict{String, String}(),
        dockerfile_update::Function = x -> x,
        build_args::Vector{Pair}
      )::LocalImage

Creates a locally-stored docker image containing the specified responder. This can be tested
tested locally, or directly uploaded to an AWS ECR Repo for use as an AWS Lambda function.

`package_compile` indicates whether `PackageCompiler.jl` should be used to compile the image -
this is not necessarily for testing/exploration but is highly recommended for production use.

Use `no_cache` to construct the local image without using a cache; this is sometimes necessary
if nothing locally has changed, but the image is querying a remote object (say, a github repo)
which has changed.

If `user_defined_labels` are defined, these will be added to the generated `LocalImage`, as well
as all subsequent types based on the `LocalImage`, like the remote image or the ultimate Lambda
function. They can be retrieved using the `get_labels` function, alongside the Jot-generated
labels.

`dockerfile_update` is a function that accepts the pre-generated Dockerfile as its only argument,
and returns a new Dockerfile. The most likely use case for this is to add customized extensions
to the generated Dockerfile. For example, passing
`(dockerfile) -> dockerfile * "RUN ssh-keygen -t rsa -f .ssh/id_rsa -N"`
will cause an SSH key to be created within the docker image.

`build_args` are appended to the `docker build` command. 
"""
function create_local_image(
    responder::AbstractResponder;
    image_suffix::Union{Nothing, String} = nothing,
    aws_config::Union{Nothing, AWSConfig} = nothing,
    image_tag::String = "latest",
    no_cache::Bool = false,
    julia_base_version::String = "1.6.1",
    julia_cpu_target::String = "x86-64",
    package_compile::Bool = false,
    user_defined_labels::AbstractDict{String, String} = OrderedDict{String, String}(),
    dockerfile_update::Function = x -> x,
    build_args::Vector{Pair}
  )::LocalImage
  # TODO check if the image suffix already exists
  image_suffix = isnothing(image_suffix) ? get_lambda_name(responder) : image_suffix
  aws_config = isnothing(aws_config) ? get_aws_config() : aws_config
  add_scripts_to_build_dir(package_compile, julia_cpu_target, responder)
  dockerfile = get_dockerfile(responder,
                              julia_base_version,
                              package_compile;
                              user_defined_labels,
                              dockerfile_update
                             )
  @debug dockerfile
  open(joinpath(responder.build_dir, "Dockerfile"), "w") do f
    write(f, dockerfile)
  end
  image_name_plus_tag = get_image_full_name_plus_tag(aws_config,
                                                     image_suffix,
                                                     image_tag)
  # Build the actual image
  build_cmd = get_dockerfile_build_cmd(dockerfile,
                                       image_name_plus_tag,
                                       no_cache,
                                       build_args)
  run(Cmd(build_cmd, dir=responder.build_dir))
  # Locate it and return it
  id_fname = joinpath(responder.build_dir, "id")
  @debug id_fname
  image_id = open(id_fname, "r") do f
    full_str = String(read(f))
    @debug full_str
    split(full_str, ':')[2]
  end
  @debug image_id
  this_image = get_local_image(image_id)
  isnothing(this_image) ? error("Unable to locate created local image with image ID $image_id") : this_image
end

function parse_docker_ls_output(::Type{T}, raw_output::AbstractString)::Vector{T} where {T}
  if raw_output == ""
    Vector{T}()
  else
    # as_lower = lowercase(raw_output)
    by_line = split(raw_output, "\n")
    as_dicts = [JSON3.read(js_str) for js_str in by_line]
    # type_args = [[dict[Symbol(fn)] for fn in fieldnames(T)] for dict in as_dicts]
    [T(; filter(p -> p.first in fieldnames(T), dict)..., exists=true) for dict in as_dicts]
  end
end

# -- get_labels --

function get_labels(res::LocalPackageResponder)::Labels
  Labels( RESPONDER_PACKAGE_NAME=res.package_name,
          RESPONDER_FUNCTION_NAME=get_responder_function_name(res),
          RESPONDER_COMMIT=get_commit(res),
          RESPONDER_TREE_HASH=get_tree_hash(res),
          RESPONDER_PKG_SOURCE=get_responder_path(res),
          IS_JOT_GENERATED="true",
         )
end

"""
    get_user_labels(l::Union{LocalImage, ECRRepo, RemoteImage, LambdaFunction})::Dict

Retrieves any user_defined labels for the given resource as a Dict of key=>value pairs.
"""
function get_user_labels(l::Union{LocalImage, ECRRepo, RemoteImage, LambdaFunction})::Dict
  get_labels(l) |> filter_user_defined_only
end

function get_labels(image::LocalImage)::Labels
  image_inspect_json = readchomp(`docker inspect $(image.ID)`)
  iis = JSON3.read(image_inspect_json, Vector{Dict{String, Any}})
  if length(iis) == 0
    error("Unable to find labels for image $(image.Repository)")
  else
    get_labels(iis[1])
  end
end

function get_labels(ecr_repo::ECRRepo)::Labels
  tags_json = readchomp(
    `aws ecr list-tags-for-resource
       --resource-arn $(ecr_repo.repositoryArn)`
  )
  tags_raw = JSON3.read(tags_json)
  haskey(tags_raw, "tags") || error("ECR Repo $(ecr_repo.repositoryName) has no tags")
  tags_dict = Dict(d["Key"] => d["Value"] for d in tags_raw["tags"])
  Labels(tags_dict)
end

function get_labels(image::RemoteImage)::Labels
  batch_image_json = readchomp(
    `aws ecr batch-get-image
      --repository-name $(image.ecr_repo.repositoryName)
      --image-id imageTag=$(image.imageTag)
      --accepted-media-types "application/vnd.docker.distribution.manifest.v1+json" --output json`
     )
  batch_image = JSON3.read(batch_image_json)
  try
    manifest = JSON3.read(batch_image["images"][1]["imageManifest"])
    v1_compat = JSON3.read(manifest["history"][1]["v1Compatibility"])
    labels = v1_compat["config"]["Labels"]
    labels = OrderedDict{Symbol, String}(labels)
    labels = OrderedDict(String(k) => v for (k, v) in labels)
    Labels(labels)
  catch e
    if isa(e, BoundsError) || isa(e, KeyError)
      error("Unable to find labels for image $(image.ecr_repo.repositoryName)")
    else
      throw(e)
    end
  end
end

function get_labels(image_inspect::AbstractDict{String, Any})::Labels
  ii = image_inspect["Config"]["Labels"]
  isnothing(ii) && error("Unable to get labels")
  ii_sym = Dict(k => v for (k, v) in ii)
  Labels(ii_sym)
end

function get_labels(lambda_function::LambdaFunction)::Labels
  get_lf_tags_script = get_lambda_function_tags_script(lambda_function)
  tags_json = readchomp(`bash -c $get_lf_tags_script`)
  try
    JSON3.read(tags_json, Dict{String, Labels})["Tags"]
  catch e
    error("Unable to find labels for lambda function $(lambda_function.FunctionName)")
  end
end

function get_labels(lc::LambdaComponents)::Labels
  if !isnothing(lc.local_image)
    get_labels(lc.local_image)
  elseif !isnothing(lc.remote_image)
    get_labels(lc.remote_image)
  else
    get_labels(lc.lambda_function)
  end
end

function is_jot_generated(c::Union{ECRRepo, LambdaComponent})::Bool
  try
    labels = get_labels(c)
    Meta.parse(labels.IS_JOT_GENERATED)
  catch e
    false
  end
end

"""
    run_test(
      image::LocalImage,
      function_argument::Any = "",
      expected_response::Any = nothing;
      then_stop::Bool = false,
    )::Tuple{Bool, Float64}

Runs a test of the given local docker image, passing `function_argument` (if given), and expecting
`expected_response`(if given). If a function_argument is not given, then it will merely test
that any kind of response is received - this response may be an error JSON and the test will still
pass, establishing only that the image can be contacted. Returns a tuple of (test result, time)
where time is the time taken for a response to be received, in seconds.

The test will use an already-running docker container, if one exists. If this is the case then the
`then_stop` parameter tells the function whether to stop the docker container after running the
test. If the run_test function finds no docker container already running, it will start one, and
then shut it down afterwards, regardless of the value of `then_stop`.
"""
function run_test(
    image::LocalImage,
    function_argument::Any = "",
    expected_response::Any = nothing;
    then_stop::Bool = false,
  )::Tuple{Bool, Float64}
  running = get_all_containers(image)
  con = length(running) == 0 ? run_image_locally(image) : nothing
  time_taken = @elapsed actual = send_local_request(function_argument)
  !isnothing(con) && (stop_container(con); delete!(con))
  then_stop && foreach(stop_container, running)
  if !isnothing(expected_response)
    passed = actual == expected_response
    passed && @info "Local test passed in $time_taken seconds; result received matched expected $actual"
    !passed && @info "Local test failed; actual: $actual was not equal to expected: $expected_response"
    (passed, time_taken)
  else
    @info "Response received from container; test passed"
    (true, time_taken)
  end
end

"""
    run_test(
      func::LambdaFunction,
      function_argument::Any = "",
      expected_response::Any = nothing;
    )::Tuple{Bool, Float64}

Runs a test of the given Lambda Function, passing `function_argument` (if given), and expecting
`expected_response`(if given). If a function_argument is not given, then it will merely test
that any kind of response is received - this response may be an error JSON and the test will still
pass, establishing only that the function can be contacted. Returns a tuple of (test result, time)
where time is the time taken for a response to be received, in seconds.
"""
function run_test(
    func::LambdaFunction,
    function_argument::Any = "",
    expected_response::Any = nothing;
    check_function_state::Bool = false,
  )::Tuple{Bool, Union{Missing, Float64}}
  try
    time_taken = @elapsed actual = invoke_function(function_argument, func; check_state = check_function_state)
    passed = actual == expected_response
    passed && @info "Remote test passed in $time_taken seconds; result received matched expected $actual"
    !passed && @info "Remote test failed; actual: $actual was not equal to expected: $expected_response"
    (passed, time_taken)
  catch e
    if isa(e, LambdaException) && isnothing(expected_response)
      @info "Error response received from lambda function; test passed"
      (true, missing)
    else
      rethrow()
    end
  end
end

function ecr_login_for_image(aws_config::AWSConfig, image_suffix::String)
  script = get_ecr_login_script(aws_config, image_suffix)
  run(`bash -c $script`)
end

function ecr_login_for_image(image::LocalImage)
  ecr_login_for_image(get_aws_config(image), get_lambda_name(image))
end

"""
    push_to_ecr!(image::LocalImage)::RemoteImage
Pushes the given local docker image to an AWS ECR Repo, a prerequisite of creating an AWS Lambda
Function. If an ECR Repo for the given local image does not exist, it will be created
automatically. Returns a RemoteImage object that represents the docker image that is hosted on the
ECR Repo. The ECR Repo itself is an attribute of the RemoteImage.
"""
function push_to_ecr!(image::LocalImage)::RemoteImage
  image.exists || error("Image does not exist")
  ecr_login_for_image(image)
  existing_repo = get_ecr_repo(image)
  repo = if isnothing(existing_repo)
    create_ecr_repo(image)
  else
    existing_repo
  end
  push_script = get_image_full_name_plus_tag(image) |> get_docker_push_script
  readchomp(`bash -c $push_script`)
  all_images = get_all_local_images()
  img_idx = findfirst(img -> img.ID[1:docker_hash_limit] == image.ID[1:docker_hash_limit], all_images)
  image.Digest = all_images[img_idx].Digest
  out = get_remote_image(image)
  @debug out
  out
end

"""
    create_lambda_function(
        remote_image::RemoteImage;
        role::Union{AWSRole, Nothing} = nothing,
        function_name::Union{Nothing, String} = nothing,
        timeout::Int64 = 60,
        memory_size::Int64 = 2000,
      )::LambdaFunction
Creates a function that exists on the AWS Lambda service. The function will use the given
`RemoteImage`, and runs using the given AWS Role.
"""
function create_lambda_function(
    remote_image::RemoteImage;
    role::Union{AWSRole, Nothing} = nothing,
    function_name::Union{Nothing, String} = nothing,
    timeout::Int64 = 60,
    memory_size::Int64 = 2000,
  )::LambdaFunction
  function_name = isnothing(function_name) ? remote_image.ecr_repo.repositoryName : function_name
  role = isnothing(role) ? create_aws_role(create_role_name(function_name)) : role
  image_uri = "$(remote_image.ecr_repo.repositoryUri):$(remote_image.imageTag)"
  @debug image_uri
  labels = get_labels(remote_image)
  out = create_lambda_function(image_uri, role, function_name, timeout, memory_size, labels)
  @debug out
  out
end

function create_role_name(function_name::String)::String
  function_name * "-generated-lambda-role"
end

"""
    create_lambda_function(
        repo::ECRRepo;
        role::AWSRole = nothing,
        function_name::Union{Nothing, String} = nothing,
        image_tag::String = "latest",
        timeout::Int64 = 60,
        memory_size::Int64 = 2000,
      )::LambdaFunction
Creates a function that exists on the AWS Lambda service. The function will use the given ECR Repo,
and runs using the given AWS Role. If given, the image_tag will decide which of the images in the
ECR Repo is used.
"""
function create_lambda_function(
    repo::ECRRepo;
    role::AWSRole = nothing,
    function_name::Union{Nothing, String} = nothing,
    image_tag::String = "latest",
    timeout::Int64 = 60,
    memory_size::Int64 = 2000,
  )::LambdaFunction
  role = isnothing(role) ? create_aws_role(get_lambda_name(repo) * "-lambda-role") : role
  function_name = isnothing(function_name) ? repo.repositoryName : function_name
  image_uri = "$(repo.repositoryUri):$image_tag"
  labels = get_labels(repo)
  create_lambda_function(image_uri, role, function_name, timeout, memory_size, labels)
end

function create_lambda_function(
    image_uri::String,
    role::AWSRole,
    function_name::String,
    timeout::Int64,
    memory_size::Int64,
    labels::Labels,
  )::LambdaFunction
  existing_lf = get_lambda_function(function_name)
  if !isnothing(existing_lf)
    @info "Lambda function $function_name already exists; overwriting"
    delete!(existing_lf)
  end
  aws_role_has_lambda_execution_permissions(role) || error("Role $role does not have permission to execute Lambda functions")
  create_script = get_create_lambda_function_script(function_name,
                                                    image_uri,
                                                    role.Arn,
                                                    timeout,
                                                    memory_size;
                                                    labels=labels,
                                                   )

  out = Pipe(); err = Pipe()
  proc = run(pipeline(ignorestatus(`bash -c $create_script`), stdout=out, stderr=err), wait=true)
  close(out.in); close(err.in)
  if proc.exitcode != 0
    @info read(err, String)
    @info read(out, String)
    error("proc exited with $(proc.exitcode)")
  end

  while true
    sleep(1)
    if get_function_state(function_name) == Active
      break
    end
  end

  func_json = read(out, String)
  return JSON3.read(func_json, LambdaFunction)
end

"""
    run_image_locally(local_image::LocalImage; detached::Bool=true)::Container

Runs the given local image, starting a docker container. If `detached`, the container will run in
the background. The container can be stopped/deleted by eg `stop_container`, `delete!`.
"""
function run_image_locally(local_image::LocalImage; detached::Bool=true)::Container
  args = ["-p", "9000:8080"]
  detached && push!(args, "-d")
  container_id = readchomp(`docker run $args $(local_image.ID)`)
  Container(ID=container_id, Image=local_image.ID)
end

"""
    send_local_request(request::Any)

Make a function call to a locally-running docker container and returns the value. A container can
be initiated by eg `run_image_locally`.
"""
function send_local_request(request::Any)
  endpoint = "http://localhost:9000/2015-03-31/functions/function/invocations"
  http = HTTP.post(
                   endpoint,
                   [],
                   JSON3.write(request),
                  )
  @debug http
  JSON3.read(http.body)
end

function get_environment_variables(image_inspect::AbstractDict{String, Any})::Dict{String, String}
  envs = image_inspect["ContainerConfig"]["Env"]
  Dict(
       env_split[1] => env_split[2] for env_split in map(x -> split(x, "="), envs)
      )
end

# -- get_lambda_name --

function get_lambda_name(res::AbstractResponder)::String
  lowercase(res.package_name)
end

function get_lambda_name(local_image::LocalImage)::Union{Nothing, String}
  @debug local_image.Repository
  is_jot_generated(local_image) ? split(local_image.Repository, '/')[2] : nothing
end

function get_lambda_name(remote_image::RemoteImage)::Union{Nothing, String}
  is_jot_generated(remote_image) ?  get_lambda_name(remote_image.ecr_repo) : nothing
end

function get_lambda_name(repo::ECRRepo)::Union{Nothing, String}
  is_jot_generated(repo) ? repo.repositoryName : nothing
end

function get_lambda_name(lf::LambdaFunction)::Union{Nothing, String}
  is_jot_generated(lf) ? lf.FunctionName : nothing
end

function get_lambda_name(l::LambdaComponents)::String
  get_from_any_component(get_lambda_name, l)
end

# -- get_response_function_name --

function get_response_function_name(
    env_vars::AbstractDict{String, String}
  )::Union{Nothing, String}
  try
    env_vars["FUNC_FULL_NAME"]
  catch e
    isa(e, KeyError) ? nothing : throw(e)
  end
end

function get_response_function_name(c::LambdaComponent)::String
  labels = get_labels(c)
  "$(labels.RESPONDER_PACKAGE_NAME).$(labels.RESPONDER_FUNCTION_NAME)"
end

function get_response_function_name(lambda::LambdaComponents)::String
  get_from_any_component(get_response_function_name, lambda)
end

end
