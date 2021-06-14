module Jot

# IMPORTS
using JSON3
using StructTypes
using Parameters
using Base.Filesystem
using LibCURL
using Dates

# EXPORTS
export AWSConfig
export ResponseFunction, Image
export get_dockerfile, build_definition
export run_image_locally, create_image, delete_image, get_images
export run_local_test, run_remote_test
export stop_container, is_container_running, get_containers, delete_container
export create_ecr_repo, delete_ecr_repo, push_to_ecr
export create_aws_role, delete_aws_role
export create_lambda_function, delete_lambda_function, invoke_function

# EXCEPTIONS
struct InterpolationNotFoundException <: Exception interpolation::String end

# CONSTANTS
const docker_hash_limit = 12

@with_kw mutable struct AWSConfig
  account_id::Union{Missing, String} = missing
  region::Union{Missing, String} = missing
end
StructTypes.StructType(::Type{AWSConfig}) = StructTypes.Mutable()  

struct ResponseFunction
  mod::Module
  response_function::Symbol

  function ResponseFunction(
      mod::Module, 
      response_function::String,
  )::ResponseFunction
    ResponseFunction(name, mod, Symbol(response_function))
  end

  function ResponseFunction(
      mod::Module,
      response_function::Symbol,
  )::ResponseFunction
    if (response_function in names(mod, all=true))
      new(mod, response_function)
    else
      throw(UndefVarError("Cannot find function $response_function in module $mod"))
    end
  end
end

@with_kw struct Image
  repository::String
  tag::String
  id::String
  createdat::Union{Missing, String} = missing
  size::Union{Missing, String} = missing
end

Base.:(==)(a::Image, b::Image) = a.id[1:docker_hash_limit] == b.id[1:docker_hash_limit]

@with_kw struct Container
  id::String
  image::String
  command::Union{Missing, String} = missing
  createdat::Union{Missing, String} = missing
  ports::Union{Missing, String} = missing
  names::Union{Missing, String} = missing
end
Base.:(==)(a::Container, b::Container) = a.id[1:docker_hash_limit] == b.id[1:docker_hash_limit]

@with_kw mutable struct ECRRepo
  repositoryArn::Union{Missing, String} = missing
  registryId::Union{Missing, String} = missing
  repositoryName::Union{Missing, String} = missing
  repositoryUri::Union{Missing, String} = missing
  createdAt::Union{Missing, String} = missing
  imageTagMutability::Union{Missing, String} = missing
  imageScanningConfiguration::Union{Missing, Any} = missing
  encryptionConfiguration::Union{Missing, Any} = missing
end
StructTypes.StructType(::Type{ECRRepo}) = StructTypes.Mutable()  
Base.:(==)(a::ECRRepo, b::ECRRepo) = a.repositoryUri == b.repositoryUri

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
end
StructTypes.StructType(::Type{LambdaFunction}) = StructTypes.Mutable()  
Base.:(==)(a::LambdaFunction, b::LambdaFunction) = (a.FunctionArn == b.FunctionArn && a.CodeSha256 == b.CodeSha256)

struct Path
  response_function::Union{Nothing, ResponseFunction}
  image::Union{Nothing, Image}
  repo::Union{Nothing, ECRRepo}
  lambda_function::Union{Nothing, LambdaFunction}
end

struct ContainersStillRunning <: Exception containers::Vector{Container} end

function get_package_path(mod::Module)::String
  module_path = Base.moduleroot(mod) |> pathof
  joinpath(splitpath(module_path)[begin:end-2]...)
end

function get_package_name(mod::Module)::String
  splitpath(get_package_path(mod))[end]
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

function get_image_full_name(image::Image)::String
  image.repository
end

function get_image_full_name_plus_tag(
    aws_config::AWSConfig, 
    image_suffix::String, 
    image_tag::String,
  )::String
  "$(get_image_full_name(aws_config, image_suffix)):$image_tag"
end

function get_image_full_name_plus_tag(image::Image)::String
  "$(image.repository):$(image.tag)"
end

function get_aws_id(image::Image)::String
  split(image.repository, '.')[1]
end

function get_aws_region(image::Image)::String
  split(image.repository, '.')[4]
end

function get_aws_config(image::Image)::AWSConfig
  AWSConfig(get_aws_id(image), get_aws_region(image))
end

function get_image_suffix(image::Image)::String
  split(image.repository, '/')[2]
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

function get_response_function_name(rf::ResponseFunction)::String
  "$(get_package_name(rf.mod)).$(rf.response_function)"
end

function is_container_running(con::Container)::Bool
  running_containers = get_containers()
  con in running_containers
end

function stop_container(con::Container)
  if is_container_running(con)
    run(`docker stop $(con.id)`)
  end
end

function delete_container(con::Container)
  run(`docker container rm $(con.id)`)
end

function move_to_temporary_build_directory(mod::Module)::String
  build_dir = mktempdir()
  cd(build_dir)
  p_path = get_package_path(mod)
  p_name = get_package_name(mod)
  @show build_dir
  Base.Filesystem.cp(p_path, joinpath(build_dir, p_name))
  build_dir
end

function write_bootstrap_to_build_directory(path::String)
  open(joinpath(path, "bootstrap"), "w") do f
    write(f, bootstrap_script)
  end
end

function create_image(
    image_suffix::String,
    rf::ResponseFunction,
    aws_config::AWSConfig; 
    image_tag::String = "latest",
    no_cache::Bool = false,
    julia_base_version::String = "1.6.1",
    julia_cpu_target::String = "x86-64",
  )::Image
  build_dir = move_to_temporary_build_directory(rf.mod)
  write_bootstrap_to_build_directory(build_dir)
  dockerfile = get_dockerfile(rf, julia_base_version)
  open(joinpath(build_dir, "Dockerfile"), "w") do f
    write(f, dockerfile)
  end
  image_name_plus_tag = get_image_full_name_plus_tag(aws_config,
                                                     image_suffix,
                                                     image_tag)
  build_cmd = get_dockerfile_build_cmd(dockerfile, 
                                       image_name_plus_tag,
                                       no_cache)
  run(build_cmd)
  image_id = open("id", "r") do f String(read(f)) end
  return Image(
    repository = get_image_full_name(aws_config, image_suffix),
    tag = image_tag,
    id = image_id,
  )
end

function split_line_by_whitespace(l::AbstractString)::Vector{String}
  filter(x -> x != "", [strip(wrd) for wrd in split(l, "   ")])
end

function parse_docker_ls_output(::Type{T}, raw_output::AbstractString)::Vector{T} where {T}
  if raw_output == ""
    Vector{T}()
  else
    as_lower = lowercase(raw_output)
    by_line = split(as_lower, "\n")
    as_dicts = [JSON3.read(js_str) for js_str in by_line]
    type_args = [[dict[Symbol(fn)] for fn in fieldnames(T)] for dict in as_dicts]
    [T(args...) for args in type_args]
  end
end

function get_image(repository::String)::Union{Nothing, Image}
  all = get_images()
  index = findfirst(x -> x.repository == repository, all)
  isnothing(index) ? nothing : all[index]
end

function get_images(args::Vector{String} = Vector{String}())::Vector{Image}
  docker_output = readchomp(`docker image ls $args --format '{{json .}}'`)
  parse_docker_ls_output(Image, docker_output)
end

function get_containers(args::Vector{String} = Vector{String}())::Vector{Container}
  docker_output = readchomp(`docker ps $args --format '{{json .}}'`)
  parse_docker_ls_output(Container, docker_output)
end

function get_containers(image::Image; args::Vector{String}=Vector{String}())::Vector{Container}
  get_containers([
                  ["--filter", "ancestor=$(image.id[begin:docker_hash_limit])"]
                  args
                 ])
end

function delete_image(image::Image; force::Bool=false)
  args = force ? ["--force"] : []
  run(`docker image rm $(image.id) $args`)
end

function run_local_test(
    image::Image,
    test_input::Any = "", 
    expected_response::Any = nothing,
  )::Bool
  running = get_containers(image)
  con = length(running) == 0 ? run_image_locally(image) : nothing
  actual = send_local_request(test_input)
  !isnothing(con) && (stop_container(con); delete_container(con))
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

function ecr_login_for_image(image::Image)
  ecr_login_for_image(get_aws_config(image), get_image_suffix(image))
end

function push_to_ecr(image::Image)::ECRRepo
  ecr_login_for_image(image)
  existing_repo = get_ecr_repo(image)
  repo = if isnothing(existing_repo)
    create_ecr_repo(image)
  else
    existing_repo
  end
  push_script = get_image_full_name_plus_tag(image) |> get_docker_push_script
  readchomp(`bash -c $push_script`)
  repo
end

function get_ecr_repo(image::Image)::Union{Nothing, ECRRepo}
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

function create_ecr_repo(image::Image)::ECRRepo
  create_script = get_create_ecr_repo_script(
                                             get_image_suffix(image),
                                             get_aws_region(image),
                                            )
  repo_json = readchomp(`bash -c $create_script`)
  @debug repo_json
  JSON3.read(repo_json, Dict{String, ECRRepo})["repository"]
end

function delete_ecr_repo(repo::ECRRepo)
  delete_script = get_delete_ecr_repo_script(repo.repositoryName)
  run(`bash -c $delete_script`)
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

function delete_aws_role(role_name::String)
  delete_script = get_delete_lambda_role_script(role_name)
  run(`bash -c $delete_script`)
end

function delete_aws_role(role::AWSRole)
  delete_script = get_delete_lambda_role_script(role.RoleName)
  run(`bash -c $delete_script`)
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

function create_lambda_function(
    repo::ECRRepo, 
    role::AWSRole;
    function_name::Union{Nothing, String} = nothing,
    image_tag::String = "latest",
    timeout::Int64 = 30,
    memory_size::Int64 = 1000,
  )::LambdaFunction
  function_name = isnothing(function_name) ? repo.repositoryName : function_name
  aws_role_has_lambda_execution_permissions(role) || error("Role $role does not have permission to execute Lambda functions")
  image_uri = "$(repo.repositoryUri):$image_tag"
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

# THIS CURRENTLY DEPRECATED, TRYING TO FIGURE OUT WHAT TO DO WITH IT
function create_lambda_function(
    name::String,
    rf::ResponseFunction,
    aws_config::AWSConfig;
    role::Union{Nothing, AWSRole} = nothing,
    image_tag::Union{Nothing, String} = nothing,
    no_cache::Union{Nothing, Bool} = nothing,
    julia_base_version::Union{Nothing, String} = nothing,
    julia_cpu_target::Union{Nothing, String} = nothing,
    timeout::Union{Nothing, Int64} = nothing,
    memory_size::Union{Nothing, Int64} = nothing,
  )::LambdaFunction
  create_image_kwarg_strings = ["image_tag", "no_cache", "julia_base_version", "julia_cpu_target"]
  create_image_kws = [
                      (str => eval(Meta.parse(str))) 
                      for str in create_image_kwarg_strings 
                      if !isnothing(eval(Meta.parse(str)))
                     ]
  image = create_image(name, rf, aws_config; create_image_kws...)
  repo = create_ecr_repo(image)
  role = isnothing(role) ? get_aws_role(name) : role
  role = isnothing(role) ? create_aws_role(name) : role

  create_lambda_function_kwarg_strings = ["image_tag", "timeout", "memory_size"]
  create_lambda_function_kws = [
                      (str => eval(Meta.parse(str))) 
                      for str in create_lambda_function_kwarg_strings 
                      if !isnothing(eval(Meta.parse(str)))
                     ]
  create_lambda_function(repo, role; create_lambda_function_kws...)
end

function delete_lambda_function(func::LambdaFunction)
  delete_script = get_delete_lambda_function_script(func.FunctionArn)
  output = readchomp(`bash -c $delete_script`)
  @debug output
end

function run_image_locally(image::Image; detached::Bool=true)::Container
  args = ["-p", "9000:8080"]
  detached && push!(args, "-d")
  container_id = readchomp(`docker run $args $(image.id)`)
  Container(id=container_id, image=image.id)
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

function get_path(rf::ResponseFunction)::Path
  Path(rf, nothing, nothing, nothing)
end

function get_path(func::LambdaFunction)::Path
   
end

function invoke_function(
    request::Any,
    lambda_function::LambdaFunction, 
  )
  request_json = JSON3.write(request)
  @debug request_json
  outfile_path = tempname()
  invoke_script = get_invoke_lambda_function_script(lambda_function.FunctionArn, 
                                                    request_json, 
                                                    outfile_path)
  @debug invoke_script
  status = readchomp(`bash -c $invoke_script`) 
  response = open(outfile_path, "w") do f
    read(f, String)
  end
  @debug response
  JSON3.read(response)
end

end
