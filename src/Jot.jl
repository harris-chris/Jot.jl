module Jot

# IMPORTS
using JSON3
using StructTypes
using Parameters
using Base.Filesystem
using LibCURL
using Dates

# EXPORTS
export AWSConfig, ImageConfig, LambdaFunctionConfig, Config
export Definition, Image
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

struct Function
  mod::Union{Nothing, Module}
  func_name::String
end

struct Definition
  mod::Union{Nothing, Module}
  func_name::String
  config::Config
  test::Union{Nothing, Tuple{Any, Any}}
end

@with_kw struct Image
  repository::String
  tag::String
  image_id::String
  created::Union{Missing, String} = missing
  size::Union{Missing, String} = missing
end

Base.:(==)(a::Image, b::Image) = a.image_id[1:docker_hash_limit] == b.image_id[1:docker_hash_limit]

@with_kw struct Container
  container_id::String
  image::Image
  command::Union{Missing, String} = missing
  created::Union{Missing, String} = missing
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

Base.:(==)(a::Container, b::Container) = a.container_id[1:docker_hash_limit] == b.container_id[1:docker_hash_limit]

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

function get_image_name(config::Config)::String
  "$(config.aws.account_id).dkr.ecr.$(config.aws.region).amazonaws.com/$(config.image.name)"
end

function get_image_tag(config::Config)::String
  "$(config.image.tag)"
end

function get_image_uri_string(config::Config)::String
  "$(get_image_name(config)):$(get_image_tag(config))"
end

function get_role_arn_string(config::Config)::String
  "arn:aws:iam::$(config.aws.account_id):role/$(config.lambda_function.role)"
end

function get_function_uri_string(config::Config)::String
  "$(config.aws.account_id).dkr.ecr.$(config.aws.region).amazonaws.com/$(config.image.name)"
end

function get_function_arn_string(config::Config)::String
  "arn:aws:lambda:$(config.aws.region):$(config.aws.account_id):function:$(config.lambda_function.name)"
end

function get_ecr_arn_string(config::Config)::String
  "arn:aws:ecr:$(config.aws.region):$(config.aws.account_id):repository/$(config.lambda_function.name)"
end

function get_ecr_uri_string(config::Config)::String
  "$(config.aws.account_id).dkr.ecr.$(config.aws.region).amazonaws.com/$(config.lambda_function.name)"
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

function get_response_function_name(def::Definition)::String
  "$(get_package_name(def.mod)).$(def.func_name)"
end

function get_dockerfile(def::Definition)::String
  get_julia_image_dockerfile(def)
end

function is_container_running(con::Container)::Bool
  running_containers = get_containers()
  con in running_containers
end

function stop_container(con::Container)
  if is_container_running(con)
    run(`docker stop $(con.container_id)`)
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

function build_image(def::Definition; no_cache::Bool=false)
  build_dir = move_to_temporary_build_directory(def.mod)
  write_bootstrap_to_build_directory(build_dir)
  @show readdir()
  dockerfile = get_dockerfile(def)
  open(joinpath(build_dir, "Dockerfile"), "w") do f
    write(f, dockerfile)
  end
  build_cmd = get_dockerfile_build_cmd(dockerfile, def.config, no_cache)
  run(build_cmd)
  image_id = open("id", "r") do f String(read(f)) end
  return Image(
    repository = get_image_name(def.config),
    tag = get_image_tag(def.config),
    image_id = image_id,
  )
end

function split_line_by_whitespace(l::AbstractString)::Vector{String}
  filter(x -> x != "", [strip(wrd) for wrd in split(l, "   ")])
end

function docker_output_to_vec_dict(raw_output::String)::Vector{Dict{String, Any}}
  by_line = split(raw_output, "\n")
  headers = map(lowercase, split_line_by_whitespace(by_line[1]))
  as_strings = by_line[2:end]
  as_vec_string = filter(!isempty, map(split_line_by_whitespace, as_strings))
  if !all([length(strs) == length(headers) for strs in as_vec_string])
    error("Unable to match docker image ls output with headers")
  end
  as_dict = [Dict(kw => str for (kw, str) in zip(headers, str)) for str in as_vec_string]
end

function get_images(args::Vector{String} = Vector{String}())::Vector{Image}
  image_ls_output = read(`docker image ls $args`, String)
  as_dicts = docker_output_to_vec_dict(image_ls_output)
  image_field_names = map(x -> String(x) |> x -> replace(x, "_" => " "), fieldnames(Image))
  image_args = [[dict[fn] for fn in image_field_names] for dict in as_dicts]
  images = [Image(i_args...) for i_args in image_args]
end

function get_containers(args::Vector{String} = Vector{String}())::Vector{Container}
  docker_ps_output = read(`docker ps $args`, String)
  as_dicts = docker_output_to_vec_dict(docker_ps_output)
  container_field_names = map(x -> String(x) |> x -> replace(x, "_" => " "), fieldnames(Container))
  images = get_images()
  get_image(img_id) = images[findfirst(x -> x.image_id == img_id, images)]
  container_args = [[fn == "image" ? get_image(dict["image"]) : dict[fn]
                     for fn in container_field_names]
                    for dict in as_dicts]
  containers = [Container(c_args...) for c_args in container_args]
end

function get_containers(image::Image)::Vector{Container}
  get_containers(["--filter", "ancestor=$(image.image_id[begin:docker_hash_limit])"])
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
  run(`docker image rm $(image.image_id)`)
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
  container_id = readchomp(`docker run $args $(image.image_id)`)
  Container(container_id=container_id, image=image)
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
