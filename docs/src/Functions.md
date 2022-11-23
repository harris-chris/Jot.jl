# Functions

```@docs
create_lambda_function(
    remote_image::RemoteImage;
    role::Union{AWSRole, Nothing} = nothing,
    function_name::Union{Nothing, String} = nothing,
    timeout::Int64 = 60,
    memory_size::Int64 = 2000,
  )
create_lambda_function(
    repo::ECRRepo;
    role::AWSRole = nothing,
    function_name::Union{Nothing, String} = nothing,
    image_tag::String = "latest",
    timeout::Int64 = 60,
    memory_size::Int64 = 2000,
  )
create_local_image(
    responder::AbstractResponder;
    image_suffix::Union{Nothing, String} = nothing,
    aws_config::Union{Nothing, AWSConfig} = nothing,
    image_tag::String = "latest",
    no_cache::Bool = false,
    julia_base_version::String = "1.8.2",
    julia_cpu_target::String = "x86-64",
    package_compile::Bool = false,
    user_defined_labels::AbstractDict{String, String} = OrderedDict{String, String}(),
    dockerfile_update::Function = x -> x,
    build_args::AbstractDict{String, String} = OrderedDict{String, String}(),
  )::LocalImage
delete!(con::Container)
delete!(repo::ECRRepo)
delete!(func::LambdaFunction)
delete!(image::LocalImage; force::Bool=false)
get_dockerfile(
    responder::AbstractResponder,
    julia_base_version::String,
    package_compile::Bool;
    user_defined_labels::AbstractDict{String, String} = AbstractDict{String, String}(),
    dockerfile_update::Function = x -> x,
  )
get_ecr_repo(image::LocalImage)
get_ecr_repo(repo_name::String)
create_lambda_components(
    res::AbstractResponder;
    image_suffix::Union{Nothing, String} = nothing,
    aws_config::Union{Nothing, AWSConfig} = nothing,
    image_tag::String = "latest",
    no_cache::Bool = false,
    julia_base_version::String = "1.8.2",
    julia_cpu_target::String = "x86-64",
    package_compile::Bool = false,
    user_defined_labels::AbstractDict{String, String} = OrderedDict{String, String}(),
    dockerfile_update::Function = x -> x,
  )
get_all_aws_roles()
get_all_containers(args::Vector{String} = Vector{String}())
get_all_ecr_repos(jot_generated_only::Bool = true)
get_all_lambda_functions(jot_generated_only::Bool = true)
get_all_local_images(; args::Vector{String} = Vector{String}(), jot_generated_only::Bool = true)
get_all_remote_images(jot_generated_only::Bool = true)
get_lambda_function(function_name::String)
get_lambda_function(repo::ECRRepo)
get_local_image(repository::String)
get_remote_image(lambda_function::LambdaFunction)
get_remote_image(local_image::LocalImage)
get_remote_image(identity::AbstractString)
get_responder(
    path_url::String,
    response_function::Symbol,
    response_function_param_type::Type;
    dependencies = Vector{String}(),
    registry_urls = Vector{String}(),
  )
get_responder(
    mod::Module,
    response_function::Symbol,
    response_function_param_type::Type;
    registry_urls::Vector{String} = Vector{String}(),
  )
get_user_labels(l::Union{LocalImage, ECRRepo, RemoteImage, LambdaFunction})
invoke_function(
    request::Any,
    lambda_function::LambdaFunction;
    debug::Bool=false,
    check_state::Bool=false,
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
run_test(l::LambdaComponents; function_argument::Any = "", expected_response::Any = nothing;)
send_local_request(request::Any)
show_lambdas()
stop_container(con::Container)
with_remote_image!(l::LambdaComponents)
with_lambda_function!(l::LambdaComponents)
```
