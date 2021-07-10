# Functions

```@docs
create_lambda_function(
    remote_image::RemoteImage,
    role::AWSRole;
    function_name::Union{Nothing, String} = nothing,
    timeout::Int64 = 60,
    memory_size::Int64 = 2000,
  )
create_lambda_function(
    repo::ECRRepo,
    role::AWSRole;
    function_name::Union{Nothing, String} = nothing,
    image_tag::String = "latest",
    timeout::Int64 = 60,
    memory_size::Int64 = 2000,
  )
create_local_image(
    image_suffix::String,
    responder::AbstractResponder;
    aws_config::Union{Nothing, AWSConfig} = nothing, 
    image_tag::String = "latest",
    no_cache::Bool = false,
    julia_base_version::String = "1.6.1",
    julia_cpu_target::String = "x86-64",
    package_compile::Bool = false,
  )
delete!(con::Container)
delete!(repo::ECRRepo)
delete!(func::LambdaFunction)
delete!(image::LocalImage; force::Bool=false)
get_dockerfile(
    responder::AbstractResponder,
    julia_base_version::String,
    package_compile::Bool,
  )
get_ecr_repo(image::LocalImage)
get_ecr_repo(repo_name::String)
get_lambda_function(function_name::String)
get_lambda_function(repo::ECRRepo)
get_local_image(repository::String)
get_remote_image(lambda_function::LambdaFunction)
get_remote_image(local_image::LocalImage)
get_responder( 
    path_url::String, 
    response_function::Symbol,
    response_function_param_type::Type;
    dependencies = Vector{String}(),
  )
get_responder(
    package_spec::Pkg.Types.PackageSpec, 
    response_function::Symbol,
    response_function_param_type::Type;
    dependencies = Vector{String}(),
  )
get_responder(
    mod::Module, 
    response_function::Symbol,
    response_function_param_type::Type,
  )
invoke_function(
    request::Any,
    lambda_function::LambdaFunction;
    check_state::Bool,
  )
is_container_running(con::Container)
push_to_ecr!(image::LocalImage)
run_image_locally(local_image::LocalImage; detached::Bool=true)
run_test(
  image::LocalImage,
  function_argument::Any = "", 
  expected_response::Any = nothing;
  then_stop::Bool = false,
)
send_local_request(request::Any)
stop_container(con::Container)
```
