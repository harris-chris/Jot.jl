using Test
using Distributed
using Pkg
using Random

Pkg.develop(PackageSpec(path="./"))
using Jot

Pkg.develop(PackageSpec(path="./test/JotTest1"))
using JotTest1

const aws_config = AWSConfig(account_id="513118378795", region="ap-northeast-1")
const test_suffix = randstring("abcdefghijklmnopqrstuvwxyz1234567890", 12)
const jot_path = pwd()

@show ARGS

function reset_response_suffix()::String
  response_suffix = randstring(12)
  open(joinpath(jot_path, "./test/JotTest1/response_suffix"), "w") do rsfile
    write(rsfile, response_suffix)
  end
  response_suffix
end

function run_tests(to::Union{Nothing, String})

  rs_suffix = reset_response_suffix()
  response_func_check(s::String)::String = s * rs_suffix

  (res, altered_res) = test_responder()
  if to == "responder"
    clean_up()
    return
  end
  
  local_image = test_local_image(res, altered_res, response_func_check)
  if to == "local_image"
    clean_up()
    return
  end

  (ecr_repo, remote_image) = test_ecr_repo(res, local_image)
  if to == "ecr_repo"
    clean_up()
    return
  end

  aws_role = test_aws_role()
  if to == "aws_role"
    clean_up()
    return
  end

  lambda_function = test_lambda_function(ecr_repo, remote_image, aws_role, response_func_check)
  if to == "lambda_function"
    clean_up()
    return
  end

  clean_up()

end

function test_responder()::Tuple{AbstractResponder, AbstractResponder}
  pkg = PackageSpec(path=joinpath(jot_path, "./test/JotTest1"))
  res = Responder(pkg, :response_func)
  # Create an altered responder and check that the two do not match
  _ = reset_response_suffix()
  altered_res = Responder(pkg, :response_func)
  @testset "Test responder" begin
    @test isa(Jot.get_tree_hash(res), String)
    @test isa(Jot.get_commit(res), String)

    @test res != altered_res 
  end
  (res, altered_res)
end

function test_local_image(
    res::AbstractResponder, 
    altered_res::AbstractResponder,
    rf_check::Function,
  )::LocalImage
  local_image = create_local_image("jot-test-image-"*test_suffix, res, aws_config)
  @testset "Test local image" begin
    @test Jot.matches(res, local_image)
    @test !Jot.matches(altered_res, local_image)
    # Test that container runs
    cont = run_image_locally(local_image)
    @test is_container_running(cont)
    conts = get_all_containers(local_image)
    @test length(conts) == 1
    foreach(stop_container, conts)
    # Check containers have stopped
    @test length(get_all_containers(local_image)) == 0
    # Run local test of container, without value
    @test run_local_test(local_image)
    # Run local test of container, with expected response
    request = randstring(4)
    expected_response = rf_check(request)
    @test run_local_test(local_image, request, expected_response)
  end

  return local_image
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
  sleep(10) # necessary; some kind of time delay in aws when creating roles
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
    request = randstring(4)
    expected_response = rf_check(request)
    while true
      Jot.get_function_state(lambda_function) == active && break
    end
    (status, response) = invoke_function(request, lambda_function)
    @test response == expected_response
    # Create the same thing using a remote image
    @test lambda_function == create_lambda_function(remote_image, aws_role; function_name="addl"*test_suffix)
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

    foreach(delete_lambda_function!, test_lfs)
    foreach(delete_ecr_repo!, test_repos)
    foreach(delete_aws_role!, test_roles)
    foreach(x -> delete_local_image!(x, force=true), test_local_images)
    foreach(delete_container!, test_containers)

    @test all([!x.exists for x in test_lfs])
    @test all([!x.exists for x in test_repos])
    @test all([!x.exists for x in test_roles])
    @test all([!x.exists for x in test_local_images])
    @test all([!x.exists for x in test_containers])
  end
end

@testset "All Tests" begin
  run_tests(length(ARGS) == 0 ? nothing : ARGS[1])
end

