module Jot

# IMPORTS
using JSON, Parameters

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
  dependencies::Array{String} = Array{String}()
  base::String = "1.6.0"
  runtime_path::String = "/var/runtime"
  julia_depot_path::String = "/var/julia"
  julia_cpu_target::String = "x86-64"
end

@with_kw struct LambdaFunctionConfig
  name::String
  role::String
  timeout::Int = 30
  memory_size::Int = 1000
end

@Base.kwdef struct Config
  aws::AWSConfig
  image::ImageConfig
  lambda_function::LambdaFunctionConfig
end

# GLOBALS
@Base.kwdef struct Builtins
  scripts_path::String
  image_path::String
  function_path::String
  template_path::String
  template_scripts_path::String
  source_files_path::String
  special_folder_names::Array{String}
  default_config_path::String
  script_templates_path::String
  required_packages::Array{String}
end

const builtins = Builtins(
  scripts_path = "./scripts",
  image_path = "./image",
  function_path = "./function",
  template_path = "./template",
  template_scripts_path = "./template/scripts",
  source_files_path = "./template/image",
  special_folder_names = ["_runtime", "_depot"],
  default_config_path = "./config.json",
  script_templates_path = "./template/scripts",
  required_packages = ["HTTP", "JSON"],
)

end
