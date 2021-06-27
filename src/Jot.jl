module Jot

# IMPORTS
using Pkg
using JSON3
using StructTypes
using Parameters
using Base.Filesystem
using LibCURL
using Dates
using IsURL
using TOML

# EXPORTS
export AWSConfig
export Responder, AbstractResponder
export LocalImage, RemoteImage, ECRRepo, AWSRole, LambdaFunction
export LambdaFunctionState, pending, active
export get_dockerfile, build_definition
export run_image_locally, create_local_image, delete_local_image!, get_local_image
export run_local_test, run_remote_test
export stop_container, is_container_running, get_all_containers, delete_container!
export create_ecr_repo, delete_ecr_repo!, push_to_ecr!
export create_aws_role, delete_aws_role!, get_all_aws_roles
export create_lambda_function, delete_lambda_function!, invoke_function

# EXCEPTIONS
struct InterpolationNotFoundException <: Exception interpolation::String end

# CONSTANTS
const docker_hash_limit = 12

@enum LambdaFunctionState pending active

@with_kw mutable struct AWSConfig
  account_id::Union{Missing, String} = missing
  region::Union{Missing, String} = missing
end
StructTypes.StructType(::Type{AWSConfig}) = StructTypes.Mutable()  

struct ModuleDefinition
  name::String
  path::String
end

function get_commit(path::String)::Union{Missing, String}
  try
    readchomp(`bash -c "PWD=pwd; cd $path; git rev-parse HEAD; cd \$PWD"`)
  catch e
    missing
  end
end


function get_commit(mod::Module)::Union{Missing, String}
  mod_path = get_package_path(mod)
  get_commit(mod_path)
end

abstract type AbstractResponder end

mutable struct LocalPackageResponder <: AbstractResponder
  pkg::Pkg.Types.PackageSpec
  response_function::Symbol
  build_dir::String
  package_name::String

  function LocalPackageResponder(
      pkg::Pkg.Types.PackageSpec,
      response_function::Symbol,
    )::LocalPackageResponder
    build_dir = create_build_directory()
    path = pkg.repo.source
    package_name = get_responder_package_name(path)
    @show get_tree_hash(path)
    move_local_to_build_directory!(build_dir, path, package_name)
    @show get_tree_hash(build_dir)
    new(pkg, response_function, build_dir, package_name)
  end

  function LocalPackageResponder(
      path::String,
      response_function::Symbol,
    )::LocalPackageResponder
    isdir(path) || error("Unable to find local directory $(path)")
    path = path[end] == '/' ? path[1:end-1] : path |> abspath
    pkg_spec = PackageSpec(path=path)
    LocalPackageResponder(pkg_spec, response_function)
  end
end

Base.:(==)(a::LocalPackageResponder, b::LocalPackageResponder) = get_tree_hash(a) == get_tree_hash(b)

function Base.show(res::LocalPackageResponder)::String
  "$(get_response_function_name(res)) from $(res.package_spec.repo.source) with tree hash $(get_tree_hash(res))"
end

function Responder(
    package_spec::Pkg.Types.PackageSpec, 
    response_function::Symbol,
)::AbstractResponder
  if !isnothing(package_spec.repo.source)
    path_url = package_spec.repo.source
    if isurl(path_url)
      # TODO URL
      error("Not implemented URL")
    elseif isrelativeurl(path_url)
      LocalPackageResponder(path_url, response_function)
    else
      error("path/url $path_url not recognized")
    end
  else
    error("Not implemented")
  end
end

function Responder(
    mod::Module, 
    response_function::Symbol,
)::LocalPackageResponder
  pkg_path = get_package_path(mod)
  LocalPackageResponder(pkg_path, response_function)
end

function get_responder_package_name(path::String)::String
  open(joinpath(path, "Project.toml"), "r") do file
    proj = file |> TOML.parse
    proj["name"]
  end
end

function get_commit(res::LocalPackageResponder)::String
  get_commit(res.build_dir)
end

function get_responder_function_name(res::LocalPackageResponder)::String
  res.response_function |> String
end

@with_kw mutable struct LocalImage
  CreatedAt::Union{Missing, String} = missing
  Digest::String
  ID::String
  Repository::String
  Size::Union{Missing, String} = missing
  Tag::String
  exists::Bool = true
end
StructTypes.StructType(::Type{LocalImage}) = StructTypes.Mutable()  
Base.:(==)(a::LocalImage, b::LocalImage) = a.ID[1:docker_hash_limit] == b.ID[1:docker_hash_limit]

@with_kw mutable struct Container
  Command::Union{Missing, String} = missing
  CreatedAt::Union{Missing, String} = missing
  ID::String
  Image::String
  Names::Union{Missing, String} = missing
  Ports::Union{Missing, String} = missing
  exists::Bool = true
end
Base.:(==)(a::Container, b::Container) = a.ID[1:docker_hash_limit] == b.ID[1:docker_hash_limit]

@with_kw mutable struct ECRRepo
  repositoryArn::Union{Missing, String} = missing
  registryId::Union{Missing, String} = missing
  repositoryName::Union{Missing, String} = missing
  repositoryUri::Union{Missing, String} = missing
  createdAt::Union{Missing, String} = missing
  imageTagMutability::Union{Missing, String} = missing
  imageScanningConfiguration::Union{Missing, Any} = missing
  encryptionConfiguration::Union{Missing, Any} = missing
  exists::Bool = true
end
StructTypes.StructType(::Type{ECRRepo}) = StructTypes.Mutable()  
Base.:(==)(a::ECRRepo, b::ECRRepo) = a.repositoryUri == b.repositoryUri

@with_kw mutable struct RemoteImage
  imageDigest::Union{Missing, String} = missing
  imageTag::Union{Missing, String} = missing
  ecr_repo::Union{Missing, ECRRepo} = missing
  exists::Bool = true
end
StructTypes.StructType(::Type{RemoteImage}) = StructTypes.Mutable()  
Base.:(==)(a::RemoteImage, b::RemoteImage) = a.imageDigest == b.imageDigest

@with_kw mutable struct AWSRolePolicyStatement
  Effect::Union{Missing, String} = missing
  Principal::Union{Missing, Dict{String, Any}} = missing
  Action::Union{Missing, String} = missing
end
StructTypes.StructType(::Type{AWSRolePolicyStatement}) = StructTypes.Mutable()  
Base.:(==)(a::AWSRolePolicyStatement, b::AWSRolePolicyStatement) = (
  a.Effect == b.Effect && a.Principal == b.Principal && a.Action == b.Action)

@with_kw mutable struct AWSRolePolicyDocument
  Version::Union{Missing, String} = missing
  Statement::Vector{AWSRolePolicyStatement} = Vector{AWSRolePolicyStatement}()
end
StructTypes.StructType(::Type{AWSRolePolicyDocument}) = StructTypes.Mutable()  
Base.:(==)(a::AWSRolePolicyDocument, b::AWSRolePolicyDocument) = (a.Version == b.Version && a.Statement == b.Statement)

const lambda_execution_policy_statement = AWSRolePolicyStatement(
    Effect = "Allow",
    Principal = Dict("Service" => "lambda.amazonaws.com"),
    Action = "sts:AssumeRole",
  )

@with_kw mutable struct AWSRole
  Path::Union{Missing, String} = missing
  RoleName::Union{Missing, String} = missing
  RoleId::Union{Missing, String} = missing
  Arn::Union{Missing, String} = missing
  CreateDate::Union{Missing, String} = missing
  AssumeRolePolicyDocument::Union{Missing, AWSRolePolicyDocument} = missing
  MaxSessionDuration::Union{Missing, Int64} = missing
  exists::Bool = true
end
StructTypes.StructType(::Type{AWSRole}) = StructTypes.Mutable()  
Base.:(==)(a::AWSRole, b::AWSRole) = a.RoleId == b.RoleId

@with_kw mutable struct LambdaFunction
  FunctionName::Union{Missing, String} = missing
  FunctionArn::Union{Missing, String} = missing
  Runtime::Union{Missing, String} = missing
  Role::Union{Missing, String} = missing
  Handler::Union{Missing, String} = missing
  CodeSize::Union{Missing, Int64} = missing
  Description::Union{Missing, String} = missing
  Timeout::Union{Missing, Int64} = missing
  MemorySize::Union{Missing, Int64} = missing
  LastModified::Union{Missing, String} = missing
  CodeSha256::Union{Missing, String} = missing
  Version::Union{Missing, String} = missing
  TracingConfig::Union{Missing, Dict{String, Any}} = missing
  RevisionId::Union{Missing, String} = missing
  PackageType::Union{Missing, String} = missing
  exists::Bool = true
end
StructTypes.StructType(::Type{LambdaFunction}) = StructTypes.Mutable()  
Base.:(==)(a::LambdaFunction, b::LambdaFunction) = (a.CodeSha256 == b.CodeSha256)

struct Lambda
  local_image::Union{Nothing, LocalImage}
  remote_image::Union{Nothing, RemoteImage}
  lambda_function::Union{Nothing, LambdaFunction}
end
Base.show(l::Lambda) = "$(l.local_image)\t$(l.remote_image)\t$(l.lambda_function)"

struct ContainersStillRunning <: Exception containers::Vector{Container} end

function get_package_path(mod::Module)::String
  module_path = Base.moduleroot(mod) |> pathof
  joinpath(splitpath(module_path)[begin:end-2]...)
end

function get_package_name(mod::Module)::String
  splitpath(get_package_path(mod))[end]
end

function get_tree_hash(res::LocalPackageResponder)::String
  @debug res.build_dir
  @debug get_tree_hash(joinpath(res.build_dir, res.package_name))
  get_tree_hash(joinpath(res.build_dir, res.package_name))
end

function get_tree_hash(path::String)::String
  Pkg.GitTools.tree_hash(path) |> bytes2hex
end

function get_package_name(mod::ModuleDefinition)::String
  mod.package_name
end

function get_registry(aws_config::AWSConfig)::String
  "$(aws_config.account_id).dkr.ecr.$(aws_config.region).amazonaws.com"
end

function get_image_full_name(
    aws_config::AWSConfig, 
    image_suffix::String,
  )::String
  "$(get_registry(aws_config))/$image_suffix"
end

function get_image_full_name(image::LocalImage)::String
  image.Repository
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

function get_aws_id(image::LocalImage)::String
  split(image.Repository, '.')[1]
end

function get_aws_region(image::LocalImage)::String
  split(image.Repository, '.')[4]
end

function get_aws_config(image::LocalImage)::AWSConfig
  AWSConfig(get_aws_id(image), get_aws_region(image))
end

function get_image_suffix(image::LocalImage)::String
  split(image.Repository, '/')[2]
end

function get_role_arn_string(
    aws_config::AWSConfig, 
    role_name::String,
  )::String
  "arn:aws:iam::$(aws_config.account_id):role/$role_name"
end

function get_function_uri_string(aws_config::AWSConfig, function_name::String)::String
  "$(aws_config.account_id).dkr.ecr.$(aws_config.region).amazonaws.com/$function_name"
end

function get_function_arn_string(aws_config::AWSConfig, function_name::String)::String
  "arn:aws:lambda:$(aws_config.region):$(aws_config.account_id):function:$function_name"
end

function get_ecr_arn_string(aws_config::AWSConfig, image_suffix::String)::String
  "arn:aws:ecr:$(aws_config.region):$(aws_config.account_id):repository/$image_suffix"
end

function get_ecr_uri_string(aws_config::AWSConfig, image_suffix::String)::String
  "$(aws_config.account_id).dkr.ecr.$(aws_config.region).amazonaws.com/$image_suffix"
end

include("BuildDockerfile.jl")
include("Runtime.jl")
include("Scripts.jl")

function get_response_function_name(res::LocalPackageResponder)::String
  "$(res.package_name).$(res.response_function)"
end

function is_container_running(con::Container)::Bool
  running_containers = get_all_containers()
  @debug running_containers
  @debug con
  con in running_containers
end

function stop_container(con::Container)
  if is_container_running(con)
    run(`docker stop $(con.ID)`)
  end
end

function delete_container!(con::Container)
  con.exists || error("Container does not exist")
  run(`docker container rm $(con.ID)`)
  con.exists = false
end

function move_local_to_build_directory!(build_dir::String, path::String, name::String)
  Base.Filesystem.cp(path, joinpath(build_dir, name))
end

function create_build_directory()::String
  build_dir = mktempdir()
  cd(build_dir)
  build_dir
end

function write_bootstrap_to_build_directory!(path::String)
  open(joinpath(path, "bootstrap"), "w") do f
    write(f, bootstrap_script)
  end
end

function write_precompile_script_to_build_directory!(path::String, package_compile::Bool)
  open(joinpath(path, "precompile.jl"), "w") do f
    write(f, get_precompile_julia_script(package_compile))
  end
end

function get_responder_add_script(
    res::LocalPackageResponder,
  )::String
  local_path = res.pkg.repo.source
  package_name = res.package_name
  add_script = dockerfile_add_target_package(package_name)
  add_script
end

function get_labels(
    res::LocalPackageResponder,
  )::Dict{String, String}
  img_labels = Dict("RESPONDER_PACKAGE_NAME" => res.package_name,
                    "RESPONDER_FUNCTION_NAME" => get_responder_function_name(res),
                    "RESPONDER_COMMIT" => get_commit(res),
                    "RESPONDER_TREE_HASH" => get_tree_hash(res),
                   )
end

function create_local_image(
    image_suffix::String,
    res::AbstractResponder,
    aws_config::AWSConfig; 
    image_tag::String = "latest",
    no_cache::Bool = false,
    julia_base_version::String = "1.6.1",
    julia_cpu_target::String = "x86-64",
    package_compile::Bool = false,
  )::LocalImage
  write_bootstrap_to_build_directory!(res.build_dir)
  write_precompile_script_to_build_directory!(res.build_dir, package_compile)
  add_script = get_responder_add_script(res)
  labels = get_labels(res)
  # TODO put dockerfile together here
  dockerfile = get_dockerfile(
                              add_script, 
                              labels, 
                              julia_base_version, 
                              res.package_name,
                              String(res.response_function),
                             )
  @debug res.build_dir
  open(joinpath(res.build_dir, "Dockerfile"), "w") do f
    write(f, dockerfile)
  end
  @debug dockerfile
  image_name_plus_tag = get_image_full_name_plus_tag(aws_config,
                                                     image_suffix,
                                                     image_tag)
  build_cmd = get_dockerfile_build_cmd(dockerfile, 
                                       image_name_plus_tag,
                                       no_cache)
  run(Cmd(build_cmd, dir=res.build_dir))
  image_id = open(joinpath(res.build_dir, "id"), "r") do f String(read(f)) end |> x -> split(x, ':')[2]
  all_images = get_all_local_images()
  short_id = image_id[1:docker_hash_limit]
  this_image = all_images[findfirst(img -> img.ID == short_id, all_images)]
  this_image
end

function split_line_by_whitespace(l::AbstractString)::Vector{String}
  filter(x -> x != "", [strip(wrd) for wrd in split(l, "   ")])
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

function get_local_image(repository::String)::Union{Nothing, LocalImage}
  all = get_all_local_images()
  index = findfirst(x -> x.Repository == repository, all)
  isnothing(index) ? nothing : all[index]
end

function get_all_local_images(args::Vector{String} = Vector{String}())::Vector{LocalImage}
  docker_output = readchomp(`docker image ls $args --digests --format '{{json .}}'`)
  parse_docker_ls_output(LocalImage, docker_output)
end

function get_all_containers(args::Vector{String} = Vector{String}())::Vector{Container}
  docker_output = readchomp(`docker ps $args --format '{{json .}}'`)
  parse_docker_ls_output(Container, docker_output)
end

function get_all_containers(image::LocalImage; args::Vector{String}=Vector{String}())::Vector{Container}
  @debug image.ID
  get_all_containers([
                  ["--filter", "ancestor=$(image.ID[1:docker_hash_limit])"]
                  args
                 ])
end

function delete_local_image!(image::LocalImage; force::Bool=false)
  image.exists || error("Image does not exist")
  args = force ? ["--force"] : []
  run(`docker image rm $(image.ID) $args`)
  image.exists = false end

function get_labels(image::LocalImage)::Dict{String, String}
  image_inspect_json = readchomp(`docker inspect $(image.ID)`)
  image_inspect = JSON3.read(image_inspect_json, Vector{Dict{String, Any}})[1]
  get_labels(image_inspect)
end

function get_labels(image::RemoteImage)::Dict{String, String}
  batch_image_json = readchomp(
    `aws ecr batch-get-image 
      --repository-name $(image.ecr_repo.repositoryName) 
      --image-id imageTag=$(image.imageTag) 
      --accepted-media-types "application/vnd.docker.distribution.manifest.v1+json" --output json`
     ) #|jq -r '.images[].imageManifest' |jq -r '.history[0].v1Compatibility' |jq -r '.config.Labels'
  batch_image = JSON3.read(batch_image_json) 
  manifest = JSON3.read(batch_image["images"][1]["imageManifest"])
  v1_compat = JSON3.read(manifest["history"][1]["v1Compatibility"])
  labels = v1_compat["config"]["Labels"]
  Dict((String(k) => v) for (k, v) in labels)
end

function run_local_test(
    image::LocalImage,
    test_input::Any = "", 
    expected_response::Any = nothing,
  )::Bool
  running = get_all_containers(image)
  con = length(running) == 0 ? run_image_locally(image) : nothing
  actual = send_local_request(test_input)
  !isnothing(con) && (stop_container(con); delete_container!(con))
  if !isnothing(expected_response)
    passed = actual == expected_response
    passed && @info "Test passed; result received matched expected $actual"
    !passed && @info "Test failed; actual: $actual was not equal to expected: $expected_test_response"
    passed
  else
    @info "Response received from container; test passed"
    true
  end
end

function ecr_login_for_image(aws_config::AWSConfig, image_suffix::String)
  script = get_ecr_login_script(aws_config, image_suffix)
  run(`bash -c $script`)
end

function ecr_login_for_image(image::LocalImage)
  ecr_login_for_image(get_aws_config(image), get_image_suffix(image))
end

function push_to_ecr!(image::LocalImage)::Tuple{ECRRepo, RemoteImage}
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
  remote_image = get_remote_image(image)
  (repo, remote_image)
end

function get_ecr_repo(image::LocalImage)::Union{Nothing, ECRRepo}
  all_repos = get_all_ecr_repos()
  image_full_name = get_image_full_name(image)
  index = findfirst(repo -> repo.repositoryUri == image_full_name, all_repos)
  isnothing(index) ? nothing : all_repos[index]
end

function create_lambda_execution_role(role_name)
  create_script = get_create_lambda_role_script(role_name)
  run(`bash -c $create_script`)
end

function get_all_ecr_repos()::Vector{ECRRepo}
  all_repos_json = readchomp(`aws ecr describe-repositories`)
  all = JSON3.read(all_repos_json, Dict{String, Vector{ECRRepo}})
  all["repositories"]
end

function get_ecr_repo(repo_name::String)::Union{Nothing, ECRRepo}
  all_repos = get_all_ecr_repos()
  index = findfirst(repo -> repo.repositoryName == repo_name, all_repos)
  isnothing(index) ? nothing : all_repos[index]
end

function create_ecr_repo(image::LocalImage)::ECRRepo
  image.exists || error("Image does not exist")
  create_script = get_create_ecr_repo_script(
                                             get_image_suffix(image),
                                             get_aws_region(image),
                                            )
  repo_json = readchomp(`bash -c $create_script`)
  @debug repo_json
  JSON3.read(repo_json, Dict{String, ECRRepo})["repository"]
end

function delete_ecr_repo!(repo::ECRRepo)
  repo.exists || error("Repo does not exist")
  delete_script = get_delete_ecr_repo_script(repo.repositoryName)
  run(`bash -c $delete_script`)
  repo.exists = false
end

function get_all_aws_roles()::Vector{AWSRole}
  all_roles_json = readchomp(`aws iam list-roles`)
  all = JSON3.read(all_roles_json, Dict{String, Vector{AWSRole}})
  all["Roles"]
end

function get_aws_role(role_name::String)::Union{Nothing, AWSRole}
  all = get_all_aws_roles()
  index = findfirst(role -> role.RoleName == role_name, all)
  isnothing(index) ? nothing : all[index]
end

function create_aws_role(role_name::String)::AWSRole
  create_script = get_create_lambda_role_script(role_name)
  role_json = readchomp(`bash -c $create_script`)
  @debug role_json
  JSON3.read(role_json, Dict{String, AWSRole})["Role"]
end

function delete_aws_role!(role::AWSRole)
  role.exists || error("Role does not exist")
  delete_script = get_delete_lambda_role_script(role.RoleName)
  run(`bash -c $delete_script`)
  role.exists = false
end

function aws_role_has_lambda_execution_permissions(role::AWSRole)::Bool
  lambda_execution_policy_statement in role.AssumeRolePolicyDocument.Statement 
end

function get_all_lambda_functions()::Vector{LambdaFunction}
  all_json = readchomp(`aws lambda list-functions`)
  JSON3.read(all_json, Dict{String, Vector{LambdaFunction}})["Functions"]
end

function get_lambda_function(function_name::String)::Union{Nothing, LambdaFunction}
  all = get_all_lambda_functions()
  index = findfirst(x -> x.FunctionName == function_name, all)
  isnothing(index) ? nothing : all[index]
end

function get_lambda_function(repo::ECRRepo)::Union{Nothing, LambdaFunction}
  all = get_all_lambda_functions()
  index = findfirst(x -> x.FunctionName == function_name, all)
  isnothing(index) ? nothing : all[index]
end

function create_lambda_function(
    remote_image::RemoteImage,
    role::AWSRole;
    function_name::Union{Nothing, String} = nothing,
    timeout::Int64 = 40,
    memory_size::Int64 = 1000,
  )::LambdaFunction
  function_name = isnothing(function_name) ? remote_image.ecr_repo.repositoryName : function_name
  image_uri = "$(remote_image.ecr_repo.repositoryUri):$(remote_image.imageTag)"
  create_lambda_function(image_uri, role, function_name, timeout, memory_size)
end

function create_lambda_function(
    repo::ECRRepo,
    role::AWSRole;
    function_name::Union{Nothing, String} = nothing,
    image_tag::String = "latest",
    timeout::Int64 = 40,
    memory_size::Int64 = 1000,
  )::LambdaFunction
  function_name = isnothing(function_name) ? repo.repositoryName : function_name
  image_uri = "$(repo.repositoryUri):$image_tag"
  create_lambda_function(image_uri, role, function_name, timeout, memory_size)
end

function create_lambda_function(
    image_uri::String,
    role::AWSRole,
    function_name::Union{Nothing, String},
    timeout::Int64,
    memory_size::Int64,
  )::LambdaFunction
  aws_role_has_lambda_execution_permissions(role) || error("Role $role does not have permission to execute Lambda functions")
  create_script = get_create_lambda_function_script(function_name,
                                                    image_uri,
                                                    role.Arn,
                                                    timeout,
                                                    memory_size,
                                                   )
  func_json = readchomp(`bash -c $create_script`)
  @debug func_json
  JSON3.read(func_json, LambdaFunction)
end

function delete_lambda_function!(func::LambdaFunction)
  func.exists || error("Function does not exist")
  delete_script = get_delete_lambda_function_script(func.FunctionArn)
  output = readchomp(`bash -c $delete_script`)
  func.exists = false 
end

function run_image_locally(image::LocalImage; detached::Bool=true)::Container
  args = ["-p", "9000:8080"]
  detached && push!(args, "-d")
  container_id = readchomp(`docker run $args $(image.ID)`)
  Container(ID=container_id, Image=image.ID)
end

function send_local_request(request::String)
  @debug request
  endpoint = "http://localhost:9000/2015-03-31/functions/function/invocations"
  http = HTTP.post(
            "http://localhost:9000/2015-03-31/functions/function/invocations",
            [],
            "\"$request\""
           )
  @debug http.body
  JSON3.read(http.body)
end

function get_environment_variables(image_inspect::AbstractDict{String, Any})::Dict{String, String}
  envs = image_inspect["ContainerConfig"]["Env"]
  Dict(
       env_split[1] => env_split[2] for env_split in map(x -> split(x, "="), envs)
      )
end

function get_labels(image_inspect::AbstractDict{String, Any})::Dict{String, String}
  image_inspect["ContainerConfig"]["Labels"]
end

function get_response_function_name(
    env_vars::AbstractDict{String, String}
  )::Union{Nothing, String}
  try
    env_vars["FUNC_FULL_NAME"]
  catch e
    if isa(e, KeyError)
      nothing
    end
  end
end

function get_response_function_name(image::LocalImage)::Union{Nothing, String}
  image_inspect_json = readchomp(`docker inspect $(image.ID)`)
  println(image_inspect_json)
  image_inspect = JSON3.read(image_inspect_json, Vector{Dict{String, Any}})[1]
  env_vars = get_environment_variables(image_inspect)
  println(env_vars)
  get_response_function_name(env_vars)
end

function get_response_function_name(images::Vector{LocalImage})::Vector{String}
  image_ids = join([img.ID for img in images], " ")
  image_inspect = JSON3.read(readchomp(`docker inspect $image_ids`))
  env_var_arr = [get_environment_variables(ii) for ii in image_inspect]
  [get_response_function_name(env_vars) for env_vars in env_var_arr]
end

function get_response_function_name(lambda::Lambda)::Union{Nothing, String}
  if !isnothing(lambda.local_image)
    get_response_function_name(local_image)
  else
    nothing
  end
end

function get_all_remote_images()::Vector{RemoteImage}
  repos = get_all_ecr_repos()
  remote_images = Vector{RemoteImage}()
  for repo in repos
    images_json = readchomp(`aws ecr list-images --repository-name=$(repo.repositoryName)`)
    images = JSON3.read(images_json, Dict{String, Vector{RemoteImage}})["imageIds"]
    for image in images
      push!(remote_images, RemoteImage(imageDigest=image.imageDigest,
                                       imageTag=image.imageTag,
                                       ecr_repo=repo))
    end
  end
  remote_images
end

function get_remote_image(local_image)::Union{Nothing, RemoteImage}
  all_remote_images = get_all_remote_images()
  index = findfirst(remote_image -> matches(local_image, remote_image), all_remote_images)
  isnothing(index) ? nothing : all_remote_images[index]
end

function matches(res::AbstractResponder, local_image::LocalImage)::Bool
  @debug get_tree_hash(res)
  @debug get_labels(local_image)["RESPONDER_TREE_HASH"]
  (get_tree_hash(res) == get_labels(local_image)["RESPONDER_TREE_HASH"])
end

function matches(local_image::LocalImage, ecr_repo::ECRRepo)::Bool
  local_image.Repository == ecr_repo.repositoryUri
end

function matches(local_image::LocalImage, remote_image::RemoteImage)::Bool
  local_image.Digest == remote_image.imageDigest
end

function matches(res::AbstractResponder, remote_image::RemoteImage)::Bool
  get_tree_hash(res) == get_labels(remote_image)["RESPONDER_TREE_HASH"]
end

function matches(remote_image::RemoteImage, lambda_function::LambdaFunction)::Bool
  hash_only = split(remote_image.imageDigest, ':')[2]
  hash_only == lambda_function.CodeSha256
end

function combine_if_matches(l1::Lambda, l2::Lambda)::Union{Nothing, Lambda}
  @unpack l1, r1, f1 = l1
  @unpack l2, r2, f2 = l2

  function sm(c1::Union{Nothing, T}, c2::Union{Nothing, T})::Tuple{Bool, T} where {T}
    if isnothing(c1)
      (true, c2)
    elseif isnothing(c2)
      (true, c1)
    else
      m = c1 == c2
      (m, m ? c1 : nothing)
    end
  end

  s_matched = (sm(l1, l2), sm(r1, r2), sm(f1, f2))
  if all(map(x -> x[1], s_matched))
    Lambda(map(last, s_matched)...)
  else
    nothing
  end
end
  
function to_table(lambdas::Vector{Lambda})::Tuple{Dict{String, Vector{String}}, Matrix{String}}
  headers = Dict("AWS Config" => ["Account ID"],
                 "Response Function" => ["Function Name", "Commit"],
                 "Local Image" => ["Image Name", "ID", "Tag"],
                 "Remote Image" => ["Tag"],
                 "Lambda Function" => ["Name", "Last Modified"],
                )
  get_datum(aws_config::AWSConfig) = [aws_config.account_id]
  get_datum(rf::AbstractResponder) = [get_response_function_name(rf), rf.commit]
  get_datum(img::LocalImage) = [get_image_suffix(img), imd.ID, img.Tag]
  get_datum(img::RemoteImage) = [img.imageTag]
  get_datum(lf::LambdaFunction) = [lf.FunctionName, lf.LastModified]

  data = [
          [isnothing(l.aws_config) ? [""] : get_datum(l.aws_config) ;
           isnothing(l.response_function) ? ["", ""] : get_datum(l.response_function) ;
           isnothing(l.local_image) ? ["", "", ""] : get_datum(l.local_image) ;
           isnothing(l.remote_image) ? [""] : get_datum(l.remote_image) ;
           isnothing(l.lambda_function) ? ["", ""] : get_datum(l.lambda_function)
          ] for l in lambdas
         ]
  (headers, data)
end

function show_lambdas()
  lambdas = get_all_lambdas()
  (headers, data) = to_table(lambdas)
  headers_matrix = ([x for (top, bottom) in headers for x in fill(top, length(bottom))],
                    [x for bottom in values(headers) for x in bottom])
  pretty_table(data; headers_matrix)
end

function get_all_lambdas()::Vector{Lambda}
  all_local = get_all_local_images()
  all_remote = get_all_remote_images()
  all_functions = get_all_lambda_functions()
  local_lambdas = [ Lambda(l, nothing, nothing) for l in all_local ]
  remote_lambdas = [ Lambda(nothing, r, nothing) for r in all_remote ]
  func_lambdas = [ Lambda(nothing, nothing, f) for f in all_functions ]
  all_lambdas = [ local_lambdas ; remote_lambdas ; func_lambdas ]

  function match_off_lambdas(
      to_match::Vector{Lambda}, 
      matched::Vector{Lambda}
  )::Vector{Lambda}
    if length(to_match) == 0
      matched
    else
      match_head = to_match[1]; match_tail = to_match[2:end]
      add_to_matched = match_head
      for m in matched
        cmb = combine_if_matches(match_head, m)
        if !isnothing(cmb) 
          add_to_matched = cmb
          break
        end
      end
      match_off_lambdas(match_tail, push!(matched, add_to_matched))
    end
  end
  match_off_lambdas(all_lambdas, Vector{Lambda}())
end

function group_by_function_name(lambdas::Vector{Lambda})::Dict{String, Vector{Lambda}}
  has_local_image = filter(l -> !isnothing(l.local_image), lambdas)
  func_names = map(l -> get_response_function_name(l.local_image), has_local_image) 
  lambdas_by_function = Dict()
  for (func_name, lambda) in zip(func_names, has_local_image)
    if !isnothing(lambda.local_image)
      if !isnothing(func_name)
        lambdas_for_name = get(lambdas_by_function, mod_func_name, Vector{Lambda}())
        lambdas_by_function[mod_func_name] = [lambdas_for_name ; [lambda]]
      end
    end
  end
  lambdas_by_function
end

function show_all_lambdas(; 
    local_image_attr::String = "tag", 
    remote_image_attr::String = "tag",  
    lambda_function_attr::String = "version",
  )
  lambdas_by_function = get_all_lambdas() |> group_by_function_name
  out = ""
  for (f_name, lambdas) in lambdas_by_function
    out *= "\n$f_name"
    # Header
    out *= "\n\tLocal Image\tRemote Image\tLambda Function"
    for lambda in lambdas
      @debug lambda
      li_attr = if local_image_attr == "tag"
        lambda.local_image.Tag
      elseif local_image_attr == "created at"
        lambda.local_image.CreatedAt
      elseif local_image_attr == "id"
        lambda.local_image.ID[1:docker_hash_limit]
      elseif local_image_attr == "digest"
        lambda.local_image.Digest[1:docker_hash_limit]
      end

      ri_attr = if isnothing(lambda.remote_image)
        ""
      else
        if remote_image_attr == "tag"
          lambda.remote_image.imageTag
        elseif remote_image_attr == "digest"
          lambda.remote_image.imageDigest[1:docker_hash_limit]
        end
      end

      lf_attr = if isnothing(lambda.lambda_function)
        ""
      else
        if lambda_function_attr == "version"
          lambda.lambda_function.Version
        elseif lambda_function_attr == "digest"
          lambda.lambda_function.CodeSha256
        end
      end
      out *= "\n\t$li_attr\t$ri_attr\t$lf_attr"
    end
  end
  println(out)
end

function get_function_state(func_name::String)::LambdaFunctionState
  state_json = readchomp(`aws lambda get-function-configuration --function-name=$func_name`)
  state_data = JSON3.read(state_json)
  if state_data["State"] == "Pending" pending
  elseif state_data["State"] == "Active" active
  end
end

function get_function_state(func::LambdaFunction)::LambdaFunctionState
  get_function_state(func.FunctionArn)
end

function invoke_function(
    request::Any,
    lambda_function::LambdaFunction, 
  )::Tuple{String, Any}
  request_json = JSON3.write(request)
  @debug request_json
  outfile_path = tempname()
  invoke_script = get_invoke_lambda_function_script(lambda_function.FunctionArn, 
                                                    request_json, 
                                                    outfile_path)
  status = readchomp(`bash -c $invoke_script`) 
  @debug status
  response = open(outfile_path, "r") do f
    read(f, String)
  end
  @debug response
  (status, JSON3.read(response))
end

end
