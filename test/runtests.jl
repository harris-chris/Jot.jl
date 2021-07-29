using Test
using Pkg
using Random

const jot_path = abspath(joinpath(pwd(), ".."))
Pkg.develop(PackageSpec(path=jot_path))
using Jot

Pkg.develop(PackageSpec(path=joinpath(jot_path, "test", "JotTest1")))
using JotTest1

const aws_config = AWSConfig(account_id="513118378795", region="ap-northeast-1")
const test_suffix = randstring("abcdefghijklmnopqrstuvwxyz1234567890", 12)

function reset_response_suffix(test_path::String)::String
  response_suffix = randstring(12)
  open(joinpath(jot_path, test_path), "w") do rsfile
    write(rsfile, response_suffix)
  end
  response_suffix
end

function get_response_suffix(test_path::String)::String
  open(joinpath(jot_path, test_path), "r") do rsfile
    readchomp(rsfile)
  end
end

struct ExpectedLabels
  RESPONDER_PACKAGE_NAME::Union{Nothing, String}
  RESPONDER_FUNCTION_NAME::String
  RESPONDER_PKG_SOURCE::String
  user_defined_labels::Dict{String, String}
end

function test_actual_labels_against_expected(
    actual::Jot.Labels,
    expected::ExpectedLabels,
  )::Bool
  @info [getfield(actual, fn) for fn in fieldnames(ExpectedLabels) if !isnothing(getfield(expected, fn))]
  @info [getfield(expected, fn) for fn in fieldnames(ExpectedLabels) if !isnothing(getfield(expected, fn))]
  all([getfield(actual, fn) == getfield(expected, fn) for fn in fieldnames(ExpectedLabels)])
end

function run_tests(; 
    clean_up::Bool=true,
    example_simple::Bool=false,
    example_components::Bool=false,
    quartet::Bool=false,
    quartet_partial::Bool=true,
    quartet_to::AbstractString="lambda_function", 
  )
  ENV["JOT_TEST_RUNNING"] = "true"
  if all([example_simple, example_components, quartet] .== false)
    example_simple = true; example_components = true; quartet = true
  end
  example_simple && run_example_simple_test(clean_up)
  example_components && run_example_components_test(clean_up)
  quartet && run_quartet_test(quartet_partial, quartet_to, clean_up)
  ENV["JOT_TEST_RUNNING"] = "false"
end

function run_example_components_test(clean_up::Bool)
  clean_up_example_test()
  @testset "Example components" begin
    # Create a simple script to use as a lambda function
    open("increment_vector.jl", "w") do f
      write(f, "increment_vector(v::Vector{Int}) = map(x -> x + 1, v)")
    end

    # Turn it into a Responder; this specifies the function we will create a Lambda from
    @info "Creating responder"
    increment_responder = get_responder("./increment_vector.jl", :increment_vector, Vector{Int})

    # Create a LambdaComponents instance from the responder
    @info "Creating LambdaComponents"
    lambda_components = create_lambda_components(increment_responder; image_suffix="increment-vector")

    lambda_components |> with_remote_image! |> with_lambda_function! |> run_test
     
    # Clean up 
    if clean_up
      delete!(lambda_components)
      rm("./increment_vector.jl")

      @test isnothing(get_local_image("increment-vector"))
      @test isnothing(get_aws_role(lambda_components.lambda_function.Role))
      @test isnothing(get_ecr_repo("increment-vector"))
      @test isnothing(get_remote_image("increment-vector"))
    end
  end
end
  

function run_example_simple_test(clean_up::Bool)
  clean_up_example_test()
  @testset "Example simple" begin
    # Create a simple script to use as a lambda function
    open("increment_vector.jl", "w") do f
      write(f, "increment_vector(v::Vector{Int}) = map(x -> x + 1, v)")
    end

    # Turn it into a Responder; this specifies the function we will create a Lambda from
    @info "Creating responder"
    increment_responder = get_responder("./increment_vector.jl", :increment_vector, Vector{Int})

    # Create a local docker image from the responder
    @info "Creating local image"
    local_image = create_local_image(increment_responder; image_suffix="increment-vector")
    @test get_local_image("increment-vector") == local_image
    @test get_lambda_name(local_image) == "increment-vector"

    # Push this local docker image to AWS ECR
    @info "Creating remote image"
    remote_image = push_to_ecr!(local_image)
    @test get_remote_image("increment-vector") == remote_image
    @test get_lambda_name(remote_image) == "increment-vector"
     
    # Create a lambda function from this remote_image... 
    @info "Creating lambda function"
    increment_vector_lambda = create_lambda_function(remote_image)
    @test get_lambda_function("increment-vector") == increment_vector_lambda
    @test get_lambda_name(increment_vector_lambda) == "increment-vector"

    # ... and test it to see if it's working OK
    @info "Testing lambda function"
    @test run_test(increment_vector_lambda, [2,3,4], [3,4,5]; check_function_state=true) |> first

    # Clean up 
    if clean_up
      delete!(increment_vector_lambda)
      delete!(remote_image)
      delete!(local_image)
      rm("./increment_vector.jl")
      @test isnothing(get_aws_role(increment_vector_lambda.Role))
      @test isnothing(get_ecr_repo("increment-vector"))
    end
    # Check that this has also cleaned up the ECR Repo and the AWS Role
  end
end

function clean_up_example_test()
  # Before the test, delete anything which might be left over
  existing_lf = get_lambda_function("increment-vector")
  !isnothing(existing_lf) && delete!(existing_lf)

  existing_ri = get_remote_image("increment-vector")
  !isnothing(existing_ri) && delete!(existing_ri)

  existing_ecr = get_ecr_repo("increment-vector")
  !isnothing(existing_ecr) && delete!(existing_ecr)

  existing_li = get_local_image("increment-vector")
  !isnothing(existing_li) && delete!(existing_li)
end

function run_quartet_test(partial::Bool, to::AbstractString, clean_up::Bool)
  reset_response_suffix("test/JotTest1/response_suffix")
  reset_response_suffix("test/JotTest2/response_suffix")

  responder_inputs = [
    ((JotTest1, :response_func, Dict), Dict()),
    ((PackageSpec(path=joinpath(jot_path, "test/JotTest2")), :response_func, Dict), Dict()),
    (("https://github.com/harris-chris/JotTest3", :response_func, Vector{Float64}), Dict()),
    ((joinpath(jot_path, "test/JotTest4/jot-test-4.jl"), :map_log_gamma, Vector{Float64}), Dict(:dependencies => ["SpecialFunctions"])),
  ]

  responders = Vector{AbstractResponder}()
  @testset "Test Responder" begin 
    foreach(responder_inputs) do input
      args = first(input)
      kwargs = last(input)
      push!(responders, test_responder(args...; kwargs)) 
    end
  end
  if to == "responder"
    clean_up && quartet_clean_up()
    return
  end

  test_data = [ # Actual, expected, bad input
    (Dict("double" => 4.5), 9.0, [1,2]),
    (Dict("add suffix" => "test-"), "test-"*get_response_suffix("test/JotTest2/response_suffix"), [1,2]),
    ([1, 2, 3, 4], Vector{Float64}([1.0, 1.0, 2.0, 6.0]), "string arg"),
    ([1, 2, 3, 4], Vector{Float64}([0.0, 0.0, 0.6931471805599453, 1.791759469228055]), Dict("this" => "that")),
  ]

  local_image_inputs = [ # Responder, number, use_config, package_compile
    (responders[1], 1, false, true),
    (responders[2], 2, true, false),
    (responders[3], 3, false, false),
    (responders[4], 4, false, false),
  ]
  user_labels = [
                 Dict("TEST"=>"1"), 
                 Dict("TEST"=>"2"),
                 Dict("TEST"=>"3"),
                 Dict("TEST"=>"4"),
                ]

  expected_labels = [
    ExpectedLabels("JotTest1", "response_func", joinpath(jot_path, "test/JotTest1"), user_labels[1]),
    ExpectedLabels("JotTest2", "response_func", joinpath(jot_path, "test/JotTest2"), user_labels[2]),
    ExpectedLabels("JotTest3", "response_func", "https://github.com/harris-chris/JotTest3", user_labels[3]),
    ExpectedLabels(
      Jot.get_package_name_from_script_name("jot-test-4.jl"), 
      "map_log_gamma", 
      joinpath(jot_path, "test/JotTest4/jot-test-4.jl"), 
      user_labels[4]),
  ]

  if !(length(responders) == length(test_data) == length(local_image_inputs))
    error("Input lengths do not match")
  end

  for res in responders
    @show res.package_name
  end

  for li in local_image_inputs
    @show li[1].package_name
  end

  local_images = Vector{LocalImage}()
  @testset "Local Images" begin
    foreach(zip(local_image_inputs, expected_labels, test_data)) do (li_inputs, labels, test_datum)
      (test_input, expected_result) = (test_datum[1], test_datum[2])
      this_li = test_local_image(li_inputs..., test_input, expected_result, labels)
      push!(local_images, this_li)
    end
  end
  
  if to == "local_image"
    clean_up && quartet_clean_up()
    return
  end

  @testset "Package compiler" begin
    test_package_compile(;
      compiled_image=local_images[1], 
      uncompiled_image=local_images[2], 
      compiled_test_data=test_data[1][1:2], 
      uncompiled_test_data=test_data[2][1:2],
    )
  end
  if to == "package_compiler"
    clean_up && quartet_clean_up()
    return
  end

  # If partial, randomly select one of our lambdas
  test_list = partial ? [i == rand(1:4) ? true : false for i in 1:4] : fill(true, length(responders))

  repos = Vector{Union{Nothing, ECRRepo}}()
  remote_images = Vector{Union{Nothing, RemoteImage}}()
  @testset "ECR Repo" begin 
    foreach(enumerate(test_list)) do (num, use_bl)
      if use_bl
        (this_repo, this_remote_image) = test_ecr_repo(responders[num], local_images[num], expected_labels[num])  
      else
        (this_repo, this_remote_image) = (nothing, nothing)
      end
      push!(repos, this_repo)
      push!(remote_images, this_remote_image)
    end
  end

  if to == "ecr_repo"
    clean_up && quartet_clean_up()
    return
  end

  aws_role = test_aws_role()
  if to == "aws_role"
    clean_up && quartet_clean_up()
    return
  end

  lambda_functions = Vector{Union{Nothing, LambdaFunction}}()
  @testset "Lambda Function" begin 
    foreach(enumerate(test_list)) do (num, use_bl)
      if use_bl
        this_lambda_function = test_lambda_function(repos[num], remote_images[num], aws_role, test_data[num]...)  
      else
        this_lambda_function = nothing
      end
      push!(lambda_functions, this_lambda_function)
    end
  end

  if to == "lambda_function"
    clean_up && quartet_clean_up()
    return
  end
  clean_up && clean_up()
end

function test_responder(
    res_obj::Any,
    res_func::Symbol,
    res_type::Type{IT};
    kwargs::Dict = Dict(),
  )::AbstractResponder{IT} where {IT}
  this_res = get_responder(res_obj, res_func, IT; kwargs...)
  @test isa(Jot.get_tree_hash(this_res), String)
  @test isa(Jot.get_commit(this_res), String)
  this_res
end

function test_local_image(
    res::AbstractResponder, 
    num::Int64,
    use_config::Bool,
    package_compile::Bool,
    test_request::Any,
    expected_test_result::Any,
    expected_labels::ExpectedLabels,
  )::LocalImage
  local_image = create_local_image(res; 
                                   aws_config = use_config ? aws_config : nothing, 
                                   package_compile = package_compile,
                                   user_defined_labels = expected_labels.user_defined_labels,
                                  )
  @test Jot.matches(res, local_image)
  @test Jot.is_jot_generated(local_image)
  @test test_actual_labels_against_expected(get_labels(local_image), expected_labels)
  # Test that container runs
  cont = run_image_locally(local_image)
  @test is_container_running(cont)
  conts = get_all_containers(local_image)
  @test length(conts) == 1
  foreach(stop_container, conts)
  # Check containers have stopped
  @test length(get_all_containers(local_image)) == 0
  # Run local test of container, without value
  @test run_test(local_image) |> first
  # Run local test of container, with expected response
  @show test_request
  @test run_test(local_image, test_request, expected_test_result; then_stop=true) |> first
  sleep(1)
  return local_image
end

function test_package_compile(;
    uncompiled_image::LocalImage,
    compiled_image::LocalImage,
    uncompiled_test_data::Tuple{Any, Any},
    compiled_test_data::Tuple{Any, Any},
  )
  @show "test_package_compile"
  sleep(2)
  @show "running test on compiled"
  @show compiled_test_data
  (_, compiled_time) = run_test(compiled_image, compiled_test_data...; then_stop=true)
  @show "first test ran"
  @show (readchomp(`docker container ls`))
  sleep(2)
  (_, uncompiled_time) = run_test(uncompiled_image, uncompiled_test_data...; then_stop=true)
  @show "second test ran"
  @test compiled_time < (uncompiled_time / 2)
end

function test_ecr_repo(
    res::AbstractResponder, 
    local_image::LocalImage, 
    expected_labels::ExpectedLabels,
  )::Tuple{ECRRepo, RemoteImage}
  remote_image = push_to_ecr!(local_image)
  ecr_repo = remote_image.ecr_repo
  @testset "Test remote image" begin 
    @test Jot.matches(local_image, ecr_repo)
    @test Jot.is_jot_generated(remote_image)
    @test test_actual_labels_against_expected(get_labels(ecr_repo), expected_labels)
    # Check we can find the repo
    @test !isnothing(Jot.get_ecr_repo(local_image))
    # Check that we can find the remote image which matches our local image
    ri_check = Jot.get_remote_image(local_image)
    @test !isnothing(ri_check)
    @test Jot.matches(local_image, remote_image)
    @test Jot.matches(res, remote_image)
  end
  (ecr_repo, remote_image)
end

function test_aws_role()::AWSRole
  aws_role =  create_aws_role("jot-test-role-"*test_suffix)
  @testset "Test AWS role" begin 
    @test aws_role in get_all_aws_roles()
  end
  aws_role
end

function test_lambda_function(
    ecr_repo::ECRRepo, 
    remote_image::RemoteImage, 
    aws_role::AWSRole,
    test_request::Any,
    expected::Any,
    exception_request::Any,
  )::LambdaFunction
  lambda_function = create_lambda_function(ecr_repo; role = aws_role)
  @testset "Lambda Function test" begin
    @test Jot.is_jot_generated(lambda_function)
    @test Jot.matches(remote_image, lambda_function)
    # Check that we can find it
    @test lambda_function in Jot.get_all_lambda_functions()
    # Invoke it 
    response = invoke_function(test_request, lambda_function; check_state=true)
    @test response == expected
    # Create the same thing using a remote image
    @test lambda_function == create_lambda_function(
      remote_image; role=aws_role, function_name="addl"*test_suffix
    )
    @test_throws LambdaException invoke_function(exception_request, lambda_function; check_state=true)
  end
  lambda_function
end

function quartet_clean_up()
  # Clean up
  # TODO clean up based on lambdas, eventually
  @show "running clean up"
  @testset "Clean up" begin
    test_lfs = [x for x in Jot.get_all_lambda_functions() if occursin(test_suffix, x.FunctionName)]
    test_repos = [x for x in Jot.get_all_ecr_repos() if occursin(test_suffix, x.repositoryName)]
    test_roles = [x for x in Jot.get_all_aws_roles() if occursin(test_suffix, x.RoleName)]
    test_local_images = [x for x in Jot.get_all_local_images() if occursin(test_suffix, x.Repository)]
    test_containers = [x for img in test_local_images for x in get_all_containers(img)]

    foreach(delete!, test_lfs)
    foreach(delete!, test_repos)
    foreach(delete!, test_roles)
    foreach(x -> delete!(x, force=true), test_local_images)
    foreach(delete!, test_containers)

    @test all([!x.exists for x in test_lfs])
    @test all([!x.exists for x in test_repos])
    @test all([!x.exists for x in test_roles])
    @test all([!x.exists for x in test_local_images])
    @test all([!x.exists for x in test_containers])
  end
end

@testset "All Tests" begin
  test_args = Dict(key => val for (key, val) in map(x -> split(x, '='), ARGS))
  test_args = Dict(Symbol(key) => (val in ["true", "false"] ? Meta.parse(val) : val) for (key, val) in test_args)
  run_tests(;test_args...)
end

