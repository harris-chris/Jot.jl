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

function reset_response_suffix()
  response_suffix = randstring(12)
  open(joinpath(jot_path, "./test/JotTest1/response_suffix"), "w") do rsfile
    write(rsfile, response_suffix)
  end
end

tc_local_images = Vector{LocalImage}()
tc_remote_images = Vector{RemoteImage}()
tc_repos = Vector{ECRRepo}()
tc_roles = Vector{ECRRoles}()
tc_containers = Vector{Container}()

run_tests()

function run_tests(to::String)

  res = test_responder()
  if to == "responder"
    clean_up()
    return
  end
  
  local_image = test_local_image(res)
  if to == "local_image"
    clean_up()
    return
  end

  ecr_repo = test_ecr_repo(local_image)
  if to == "ecr_repo"
    clean_up()
    return
  end

  aws_role = test_aws_role()
  if to == "aws_role"
    clean_up()
    return
  end

  lambda_function = test_lambda_function(ecr_repo, aws_role)
  if to == "lambda_function"
    clean_up()
    return
  end

end

function test_responder()::AbstractResponder
  reset_response_suffix()
  pkg = PackageSpec(path="./test/JotTest1")
  res = Responder(lp_pkg, :response_func)
  @testset "Test responder" begin
    @test isa(Jot.get_tree_hash(res), String)
    @test isa(Jot.get_commit(res), String)
  end
  res
end

function test_local_image(res::AbstractResponder)::LocalImage
  local_image = create_image("li"*test_suffix, res, aws_config)
  @testset "Test local image" begin
    @test Jot.matches(res, local_image)
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
    expected_response = JotTest1.response_func(request)
    @test run_local_test(local_image, request, expected_response)
  end

  return local_image
end

function test_ecr_repo(local_image::LocalImage)::ECRRepo
  ecr_repo = push_to_ecr!(local_image)
  @testset "Test remote image" begin 
    @test matches(local_image, ecr_repo)
    # Check we can find the repo
    @test !isnothing(Jot.get_ecr_repo(local_image))
    # Check that we can find the remote image which matches our local image
    remote_image = Jot.get_remote_image(local_image)
    @test !isnothing(remote_image)
    @test matches(local_image, remote_image)
  end
  ecr_repo
end

function test_aws_role()::AWSRole
  aws_role =  create_aws_role("role"*test_suffix)
  @testset "Test AWS role" begin 
    @test aws_role in get_all_aws_roles()
  end
  aws_role
end

function test_lambda_function(ecr_repo::ECRRepo, aws_role::AWSRole)::LambdaFunction
  lambda_function = create_lambda_function(ecr_repo, aws_role)
  @testset "Lambda Function test" begin
    @test matches(ecr_repo, lambda_function)
    # Check that we can find it
    @test lambda_function in Jot.get_all_lambda_functions()
    # Invoke it 
    request = randstring(4)
    expected_response = JotTest1.response_func(request)
    while true
      Jot.get_function_state(lambda_function) == active && break
    end
    (status, response) = invoke_function(request, lambda_function)
    @test response == expected_response
  end
  lambda_function
end

function clean_up()
  # Clean up
  # TODO clean up based on lambdas, eventually
  @testset "Clean up" begin
    test_lfs = [x for x in get_all_lambda_functions() if test_suffix in x.FunctionName]
    test_repos = [x for x in get_all_ecr_repos() if test_suffix in x.repositoryName]
    test_roles = [x for x in get_all_aws_roles() if test_suffix in x.RoleName]
    test_local_images = [x for x in get_all_local_image() if test_suffix in x.Repository]
    test_containers = [x for img in test_local_images for x in get_all_containers(img)]

    foreach(delete_lambda_function, test_lfs)
    foreach(delete_ecr_repo, test_repos)
    foreach(delete_aws_role, test_roles)
    foreach(delete_local_image, test_local_images)
    foreach(delete_container, test_containers)

    @test all([isnothing(x) for x in test_lfs])
    @test all([isnothing(x) for x in test_repos])
    @test all([isnothing(x) for x in test_roles])
    @test all([isnothing(x) for x in test_local_images])
    @test all([isnothing(x) for x in test_containers])
  end
end
  
