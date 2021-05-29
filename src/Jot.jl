module Jot

# IMPORTS
using JSON3
using StructTypes
include("BuildDockerfile.jl")

# EXPORTS
export AWSConfig, ImageConfig, LambdaFunctionConfig, Config
export Definition, Image

# EXCEPTIONS
struct InterpolationNotFoundException <: Exception 
  interpolation::String
end

@with_kw mutable struct AWSConfig
  account_id::Union{Missing, String} = missing
  region::Union{Missing, String} = missing
end

@with_kw mutable struct ImageConfig
  name::Union{Missing, String} = missing
  tag::String = "latest"
  dependencies::Vector{String} = []
  julia_version::String = "1.6.0"
  julia_cpu_target::String = "x86-64"
end

@with_kw mutable struct LambdaFunctionConfig
  name::Union{Missing, String} = missing
  role::String = "LambdaExecutionRole"
  timeout::Int = 30
  memory_size::Int = 1000
end

@with_kw mutable struct Config
  aws::AWSConfig = AWSConfig()
  image::ImageConfig = ImageConfig()
  lambda_function::LambdaFunctionConfig = LambdaFunctionConfig()
end

StructTypes.StructType(::Type{Config}) = StrucTypes.Mutable()  

function get_config(
    config_fpath::String;
  )::Config
  
  config = Config()
  open(fname, "r") do f
    json_string = read(f, String)
    JSON3.read!(json_string, config)
    config
  end
  @show config
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

function Config(
  aws_account_id::String,
  aws_region::String,
  function_name::String,
)::Config
  Config(
    AWSConfig(account_id = aws_account_id, region = aws_region),
    ImageConfig(name = function_name),
    LambdaFunctionConfig(name = function_name), 
  )
end

function buildDefinition(mod::Module, func_name::String)
  mod_names = names(mod, all=true)
  
  # check that func_name is in mod_names
  
end

function buildImage(def::Definition)::Image
     
end

function getDockerfile(def::Definition)::String
    
end

struct Definition
  mod::Union{Nothing, Module}
  func_name::String
  config::Config
  dockerfile::String
end

Base.@kwdef struct InvocationResponse
  response::String
end

Base.@kwdef struct InvocationError
  errorType::String
  errorMessage::String
end

end
