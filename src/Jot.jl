module Jot

# IMPORTS
using JSON3
using StructTypes
using Parameters
using Base.Filesystem

# EXPORTS
export AWSConfig, ImageConfig, LambdaFunctionConfig, Config
export Definition, Image
export get_config, get_dockerfile, build_definition, build_image

# EXCEPTIONS
struct InterpolationNotFoundException <: Exception 
  interpolation::String
end

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

struct Definition
  mod::Union{Nothing, Module}
  func_name::String
  config::Config
end

struct Image
  definition::Definition
  name::String
  tag::String
  image_id::String
end

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
    raw"$(image.base)" => config.image.base,
    raw"$(image.runtime_path)" => config.image.runtime_path,
    raw"$(image.julia_depot_path)" => config.image.julia_depot_path,
    raw"$(image.julia_cpu_target)" => config.image.julia_cpu_target,
    raw"$(image.image_uri_string)" => get_image_uri_string(config),
    raw"$(image.ecr_arn_string)" => get_ecr_arn_string(config),
    raw"$(image.ecr_uri_string)" => get_ecr_uri_string(config),
    raw"$(image.function_uri_string)" => get_function_uri_string(config),
    raw"$(image.function_arn_string)" => get_function_arn_string(config),
    raw"$(lambda_function.name)" => config.lambda_function.name,
    raw"$(lambda_function.timeout)" => config.lambda_function.timeout,
    raw"$(lambda_function.memory_size)" => config.lambda_function.memory_size,
    raw"$(lambda_function.test_invocation_body)" => get_test_invocation_body(
       joinpath(builtins.function_path, "function.jl")),
    raw"$(lambda_function.test_invocation_response)" => get_test_invocation_response(
       joinpath(builtins.function_path, "function.jl")),
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

function get_image_uri_string(config::Config)::String
  "$(config.aws.account_id).dkr.ecr.$(config.aws.region).amazonaws.com/$(config.image.name):$(config.image.tag)"
end

function get_role_arn_string(config::Config)::String
  "arn:aws:iam::$(config.aws.account_id):role/$(config.aws.role)"
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

function build_definition(mod::Module, func_name::String)::Definition
  mod_names = names(mod, all=true)
end

function get_dockerfile(def::Definition)::String
  get_julia_image_dockerfile(def)
end

function move_to_temporary_build_directory(mod::Module)
  build_dir = mktempdir()
  cd(build_dir)
  p_path = get_package_path(mod)
  p_name = get_package_name(mod)
  @show build_dir
  Base.Filesystem.cp(p_path, joinpath(build_dir, p_name))
  build_dir
end

function build_image(def::Definition; no_cache::Bool=false)
  build_dir = move_to_temporary_build_directory(def.mod)
  dockerfile = get_dockerfile(def)
  open(joinpath(build_dir, "Dockerfile"), "w") do f
    write(f, dockerfile)
  end
  build_cmd = get_dockerfile_build_cmd(dockerfile, def.config, no_cache)
  # build_with_dockerfile = pipeline(`echo $dockerfile`, build_cmd)
  out = run(build_cmd)
  @show out
end

end
