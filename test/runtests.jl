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

function reset_jt1_response_suffix()::String
  response_suffix = randstring(12)
  open(joinpath(jot_path, "test/JotTest1/response_suffix"), "w") do rsfile
    write(rsfile, response_suffix)
  end
  response_suffix
end

function run_tests(; 
    to::AbstractString="lambda_function", 
    package_compile::Bool=false, 
    clean::Bool=true,
    example_only::Bool=false,
  )
  if example_only
    test_documentation_example()
    return
  end
  package_compile = package_compile == "true" ? true : false
  clean = clean == "true" ? true : false
  rs_suffix = reset_jt1_response_suffix()
  function jt1_suffix_response_check(d::Dict)
    if haskey(d, "add suffix")
      d["add suffix"] * rs_suffix
    elseif haskey(d, "double")
      d["double"] * 2
    end
  end

  (jt1_res, jt1_alt_res, jt2_res) = test_responder(jt1_suffix_response_check)
  if to == "responder"
    clean && clean_up()
    return
  end
  
  (jt1_local, jt2_local) = test_local_image(jt1_res, jt1_alt_res, jt2_res, jt1_suffix_response_check, package_compile)
  if to == "local_image"
    clean && clean_up()
    return
  end

  (ecr_repo, remote_image) = test_ecr_repo(jt1_res, jt1_local)
  if to == "ecr_repo"
    clean && clean_up()
    return
  end

  aws_role = test_aws_role()
  if to == "aws_role"
    clean && clean_up()
    return
  end

  lambda_function = test_lambda_function(ecr_repo, remote_image, aws_role, jt1_suffix_response_check)
  if to == "lambda_function"
    clean && clean_up()
    return
  end
  clean && clean_up()
end

function test_documentation_example()
  @testset "Documentation example" begin
    # Create a simple script to use as a lambda function
    open("increment_vector.jl", "w") do f
      write(f, "increment_vector(v::Vector{Int}) = map(x -> x + 1, v)")
    end

    # Turn it into a Responder; this specifies the function we will create a Lambda from
    increment_responder = get_responder("./increment_vector.jl", :increment_vector, Vector{Int})

    # Create a local docker image from the responder
    local_image = create_local_image("increment-vector", increment_responder)

    # Push this local docker image to AWS ECR; create an AWS role that can execute it
    (ecr_repo, remote_image) = push_to_ecr!(local_image)
    aws_role = create_aws_role("increment-vector-role")
     
    # Create a lambda function from this remote_image... 
    increment_vector_lambda = create_lambda_function(remote_image, aws_role)

    # ... and test it to see if it's working OK
    @test run_test(increment_vector_lambda, [2,3,4], [3,4,5]; check_function_state=true) |> first

    # Clean up 
    delete!(increment_vector_lambda)
    delete!(ecr_repo)
    delete!(aws_role)
    delete!(local_image)
    rm("./increment_vector.jl")
  end
end

function test_responder(
    jt1_rf_check::Function,
  )::Tuple{AbstractResponder, AbstractResponder, AbstractResponder}
  jt1_pkg = PackageSpec(path=joinpath(jot_path, "./test/JotTest1"))
  jt1_res = get_responder(jt1_pkg, :response_func, Dict)
  # Create an altered responder and check that the two do not match
  @testset "Test original JT1 responder" begin
    @test jt1_rf_check(Dict("add suffix" => "t")) == JotTest1.response_func(Dict("add suffix" => "t"))
    @test jt1_rf_check(Dict("double" => 2.4)) == JotTest1.response_func(Dict("double" => 2.4))
    @test isa(Jot.get_tree_hash(jt1_res), String)
    @test isa(Jot.get_commit(jt1_res), String)
  end
  _ = reset_jt1_response_suffix()
  jt1_alt_res = get_responder(jt1_pkg, :response_func, Dict)
  @testset "Test responder" begin
    @test jt1_rf_check(Dict("add suffix" => "t")) != JotTest1.response_func(Dict("add suffix" => "t"))
    @test jt1_res != jt1_alt_res 
  end
  jt2_res = get_responder(joinpath(jot_path, "./test/JotTest2/response_func.jl"), 
                      :response_func, 
                      Vector{Float64}; 
                      dependencies=["SpecialFunctions"])
  (jt1_res, jt1_alt_res, jt2_res)
end

function test_local_image(
    jt1_res::AbstractResponder, 
    jt1_alt_res::AbstractResponder,
    jt2_res::AbstractResponder,
    jt1_rf_check::Function,
    package_compile::Bool,
  )::Tuple{LocalImage, LocalImage}
  jt1_local = create_local_image("jt1-local-"*test_suffix, jt1_res; aws_config, package_compile = package_compile)
  jt2_local = create_local_image("jt2-local-"*test_suffix, jt2_res; package_compile = false)
  @testset "Test local image" begin
    @test Jot.matches(jt1_res, jt1_local)
    @test !Jot.matches(jt1_alt_res, jt1_local)
    # Test that container runs
    cont = run_image_locally(jt1_local)
    @test is_container_running(cont)
    conts = get_all_containers(jt1_local)
    @test length(conts) == 1
    foreach(stop_container, conts)
    # Check containers have stopped
    @test length(get_all_containers(jt1_local)) == 0
    # Run local test of container, without value
    @test run_test(jt1_local) |> first
    # Run local test of container, with expected response
    request = Dict("add suffix" => randstring(4))
    expected_response = jt1_rf_check(request)
    @test run_test(jt1_local, request, expected_response) |> first

    request = Dict("double" => 4.5)
    expected_response = request["double"] * 2
    (result, jt1_time) = run_test(jt1_local, request, expected_response; then_stop=true)
    @test result

    request = [1, 2, 3, 4]
    expected_response = Vector{Float64}([0.0, 0.0, 0.6931471805599453, 1.791759469228055])
    (result, jt2_time) = run_test(jt2_local, request, expected_response)
    @test result

    package_compile && @test jt1_time < (jt2_time / 2)
  end
  return (jt1_local, jt2_local)
end

function test_ecr_repo(res::AbstractResponder, local_image::LocalImage)::Tuple{ECRRepo, RemoteImage}
  (ecr_repo, remote_image) = push_to_ecr!(local_image)
  @testset "Test remote image" begin 
    @test Jot.matches(local_image, ecr_repo)
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
    rf_check::Function,
  )::LambdaFunction
  lambda_function = create_lambda_function(ecr_repo, aws_role)
  @testset "Lambda Function test" begin
    @test Jot.matches(remote_image, lambda_function)
    # Check that we can find it
    @test lambda_function in Jot.get_all_lambda_functions()
    # Invoke it 
    request = Dict("add suffix" => randstring(4))
    expected_response = rf_check(request)
    response = invoke_function(request, lambda_function; check_state=true)
    @test response == expected_response
    # Create the same thing using a remote image
    @test lambda_function == create_lambda_function(
      remote_image, aws_role; function_name="addl"*test_suffix
    )
    @test_throws LambdaException invoke_function([1,2], lambda_function; check_state=true)
  end
  lambda_function
end

function clean_up()
  # Clean up
  # TODO clean up based on lambdas, eventually
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

