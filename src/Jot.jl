module Jot

# IMPORTS
using JSON, Parameters

# EXPORTS
export AWSConfig, ImageConfig, LambdaFunctionConfig, Config
export ImageDefinition, Image
export set_lambda_function

# EXCEPTIONS
struct InterpolationNotFoundException <: Exception 
  interpolation::String
end

@with_kw struct AWSConfig
  account_id::String
  region::String
end

@with_kw struct ImageConfig
  name::String
  tag::String = "latest"
  dependencies::Vector{String} = []
  base::String = "1.6.0"
  runtime_path::String = "/var/runtime"
  julia_depot_path::String = "/var/julia"
  julia_cpu_target::String = "x86-64"
end

@with_kw struct LambdaFunctionConfig
  name::String
  role::String = "LambdaExecutionRole"
  timeout::Int = 30
  memory_size::Int = 1000
end

@with_kw struct Config
  aws::AWSConfig
  image::ImageConfig
  lambda_function::LambdaFunctionConfig
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

mutable struct ImageDefinition
  func_expr::Union{Nothing, Expr}
  config::Union{Nothing, Config}
end

function ImageDefinition()::ImageDefinition
  ImageDefinition(nothing, nothing)
end

function ImageDefinition(config::Config)::ImageDefinition
  ImageDefinition(nothing,  config)
end

macro set_lambda_function(image_definition, f_expr)
  Expr(:(=), :($(esc(image_definition)).func_expr), Expr(:quote, f_expr))
end

macro set_lambda_function1(image_definition, f_expr)
  return quote
    local id = eval($(esc(image_definition)))
    id.func_expr = :(eval($$(esc(f_expr))))
  end
end

macro set_lambda_function2(image_definition, f_expr)
  return quote
    local id = eval($(esc(image_definition)))
    id.func_expr = esc($(esc(f_expr)))
  end
end

Base.@kwdef struct InvocationResponse
  response::String
end

Base.@kwdef struct InvocationError
  errorType::String
  errorMessage::String
end

end
