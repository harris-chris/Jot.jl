module Jot

# IMPORTS
using JSON3
using StructTypes
using Parameters
using Base.Filesystem
using LibCURL
using Dates

# EXPORTS
export AWSConfig, LambdaFunctionConfig, Config
export ResponseFunction, Image
export get_config, get_dockerfile, build_definition
export run_image_locally, build_image, delete_image, get_images
export run_local_test, run_remote_test
export stop_container, is_container_running, get_containers

# EXCEPTIONS
struct InterpolationNotFoundException <: Exception interpolation::String end

# CONSTANTS
const docker_hash_limit = 12

@with_kw mutable struct AWSConfig
  account_id::Union{Missing, String} = missing
  region::Union{Missing, String} = missing
end
StructTypes.StructType(::Type{AWSConfig}) = StructTypes.Mutable()  

@with_kw mutable struct ImageConfig
  name::Union{Missing, String} = missing
  tag::String = "latest"
  dependencies::Vector{String} = []
  julia_version::String = "1.6.0"
  julia_cpu_target::String = "x86-64"
end
StructTypes.StructType(::Type{ImageConfig}) = StructTypes.Mutable()  

@with_kw mutable struct LambdaFunctionConfig
  name::Union{Missing, String} = missing
  role::String = "LambdaExecutionRole"
  timeout::Int = 30
  memory_size::Int = 1000
end
StructTypes.StructType(::Type{LambdaFunctionConfig}) = StructTypes.Mutable()  

@with_kw mutable struct Config
  aws::AWSConfig = AWSConfig()
  image::ImageConfig = ImageConfig()
  lambda_function::LambdaFunctionConfig = LambdaFunctionConfig()
end
StructTypes.StructType(::Type{Config}) = StructTypes.Mutable()  

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

@with_kw mutable struct AWSRepository
  repositoryArn::Union{Missing, String} = missing
  registryId::Union{Missing, String} = missing
  repositoryName::Union{Missing, String} = missing
  repositoryUri::Union{Missing, String} = missing
  createdAt::Union{Missing, String} = missing
  imageTagMutability::Union{Missing, String} = missing
  imageScanningConfiguration::Union{Missing, Any} = missing
  encryptionConfiguration::Union{Missing, Any} = missing
end
StructTypes.StructType(::Type{AWSRepository}) = StructTypes.Mutable()  

Base.:(==)(a::Container, b::Container) = a.id[1:docker_hash_limit] == b.id[1:docker_hash_limit]

struct ContainersStillRunning <: Exception containers::Vector{Container} end

function get_package_path(mod::Module)::String
  module_path = Base.moduleroot(mod) |> pathof
  joinpath(splitpath(module_path)[begin:end-2]...)
end

function get_package_name(mod::Module)::String
  splitpath(get_package_path(mod))[end]
end

function interpolate_string_with_config(
    str::String,
    config::Config,
  )::String
  mappings = Dict(
    raw"$(aws.account_id)" => config.aws.account_id,
    raw"$(aws.region)" => config.aws.region,
    raw"$(aws.role)" => config.lambda_function.role,
    raw"$(aws.role_arn_string)" => get_role_arn_string(config),
    raw"$(image.name)" => config.image.name,
    raw"$(image.tag)" => config.image.tag,
    raw"$(image.julia_version)" => config.image.julia_version,
    raw"$(image.runtime_path)" => "/var/runtime",
    raw"$(image.julia_depot_path)" => "/var/julia",
    raw"$(image.julia_cpu_target)" => config.image.julia_cpu_target,
    raw"$(image.image_uri_string)" => get_image_uri_string(config),
    raw"$(image.ecr_arn_string)" => get_ecr_arn_string(config),
    raw"$(image.ecr_uri_string)" => get_ecr_uri_string(config),
    raw"$(image.function_uri_string)" => get_function_uri_string(config),
    raw"$(image.function_arn_string)" => get_function_arn_string(config),
    raw"$(lambda_function.name)" => config.lambda_function.name,
    raw"$(lambda_function.timeout)" => config.lambda_function.timeout,
    raw"$(lambda_function.memory_size)" => config.lambda_function.memory_size,
  )
  aws_matches = map(x -> x.match, eachmatch(r"\$\(aws.[a-z\_]+\)", str))
  image_matches = map(x -> x.match, eachmatch(r"\$\(image.[a-z\_]+\)", str))
  lambda_function_matches = map(x -> x.match, eachmatch(r"\$\(lambda_function.[a-z\_]+\)", str))
  all_matches = [aws_matches ; image_matches ; lambda_function_matches]

  for var_match in all_matches 
    try 
      str = replace(str, var_match => mappings[var_match])
    catch e
      if isa(e, KeyError)
        throw(InterpolationNotFoundException(var_match))
      end
    end
  end
  str
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

function get_image_full_name_plus_tag(
    aws_config::AWSConfig, 
    image_suffix::String, 
    image_tag::String,
  )::String
  "$(get_image_full_name(aws_config, image_suffix)):$image_tag"
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

function get_config(
    config_fpath::String;
  )::Config
  
  config = Config()
  open(config_fpath, "r") do f
    json_string = read(f, String)
    JSON3.read!(json_string, config)
    @info "Config file successfully loaded"
    config
  end
end

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

function build_image(
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

function get_images(args::Vector{String} = Vector{String}())::Vector{Image}
  docker_output = readchomp(`docker image ls $args --format '{{json .}}'`)
  parse_docker_ls_output(Image, docker_output)
end

function get_containers(args::Vector{String} = Vector{String}())::Vector{Container}
  docker_output = readchomp(`docker ps $args --format '{{json .}}'`)
  parse_docker_ls_output(Container, docker_output)
end

function get_containers(image::Image)::Vector{Container}
  get_containers(["--filter", "ancestor=$(image.id[begin:docker_hash_limit])"])
end

function delete_image(image::Image; force::Bool=false)
  containers = get_containers(image)
  if length(containers) > 0
    if force
      for con in containers
        stop_container(con) 
      end
    else
      throw(ContainersStillRunning(containers))
    end
  end
  run(`docker image rm $(image.id)`)
end

function run_local_test(image::Image, test_input::Any, expected_test_response::Any)::Bool
  running = get_containers(image)
  con = length(running) == 0 ? run_image_locally(image) : nothing
  actual = send_local_request(test_input)
  !isnothing(con) && stop_container(con)
  passed = actual == expected_test_response
  if passed
    @info "Test passed"
  else
    @info "Test failed"
    @info "Actual: $actual"
    @info "Expected: $expected_test_response"
  end
  passed
end

function test_image_remotely(image::Image)::Bool

end

function login_to_ecr(config::Config)
  interp = interpolate_string_with_config(ecr_login, config)
  run(`bash -c $interp`)
end

function get_repositories(config::Config)::Vector{AWSRepository}
  all_repos = read(`aws ecr describe-repositories`, String)
  @debug all_repos
  all = JSON3.read(all_repos, Dict{String, Vector{AWSRepository}})
  all["repositories"]
end

function does_ecr_repository_exist(config::Config)::Bool
  ecr_uri = get_ecr_uri_string(config)
  any([repo.repositoryUri == ecr_uri for repo in get_repositories(config)])
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

end
