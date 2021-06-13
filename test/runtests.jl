using Test
using Distributed
using Pkg
using Random

Pkg.develop(PackageSpec(path="./"))
using Jot

aws_config = AWSConfig(account_id="513118378795", region="ap-northeast-1")
test_suffix = randstring("abcdefghijklmnopqrstuvwxyz", 12)

@testset "Local Module" begin
  response_suffix = randstring(12)
  open("./test/JotTest1/response_suffix", "w") do rsfile
    write(rsfile, response_suffix)
  end
  Pkg.develop(PackageSpec(path="./test/JotTest1"))
  using JotTest1

  @testset "Build test" begin
    @test_throws MethodError ResponseFunction(JotTest1, :bad_function_name)
  end

  jt1_function = ResponseFunction(JotTest1, :response_func)
  jt1_image_name = "jot-test-1" * test_suffix
  jt1_role_name = "jt1-execution-role" * test_suffix

  jt1_image = create_image(jt1_image_name, jt1_function, aws_config)
  @testset "Local test" begin
    # Test that container runs
    jt1_cont = run_image_locally(jt1_image)
    @test is_container_running(jt1_cont)
    jt1_conts = get_containers(jt1_image)
    @test length(jt1_conts) == 1
    for cont in jt1_conts
      stop_container(cont)
    end
    # Check container has stopped
    @test length(get_containers(jt1_image)) == 0
    # Run local test of container, without value
    @test run_local_test(jt1_image)
    # Run local test of container, with expected response
    request = randstring(4)
    expected_response = JotTest1.response_func(request)
    @test run_local_test(jt1_image, request, expected_response)
  end

  jt1_repo = push_to_ecr(jt1_image)
  @testset "ECR test" begin 
    # Check we can find it
    @test !isnothing(Jot.get_ecr_repo(jt1_image))
  end

  jt1_role = create_aws_role(jt1_role_name)
  @testset "AWS Role test" begin
    # Check we can find it
    @test jt1_role == Jot.get_aws_role(jt1_role_name)
    # Verify it has execution permission
    @test Jot.aws_role_has_lambda_execution_permissions(jt1_role)
  end

  jt1_lambda_function = create_lambda_function(jt1_repo, jt1_role)
  @testset "AWS Function test" begin
    # Check that we can find it
    @test jt1_lambda_function == Jot.get_lambda_function(jt1_image_name)
    
    # Create function, with different name
    jt1_lambda_function_name = "jt1-lambda-function"
    jt1_lambda_function = create_lambda_function(jt1_repo, 
                                                 jt1_role, 
                                                 function_name = jt1_lambda_function_name)
    # Check that we can find it
    @test jt1_lambda_function == Jot.get_lambda_function(jt1_lambda_function_name)
    # Invoke it 
    request = randstring(4)
    expected_response = JotTest1.response_func(request)
    response = invoke_function(request, jt1_lambda_function)
    @test response == expected_response
  end
  
  # Clean up
  @testset "Clean up" begin
    # Delete lambda_function
    delete_lambda_function(jt1_lambda_function)
    # Check it's deleted
    @test isnothing(Jot.get_lambda_function(jt1_image_name))

    # Stop all containers
    jt1_conts = get_containers(jt1_image, args=["--all"])
    for cont in jt1_conts
      stop_container(cont)
      delete_container(cont)
    end
    # Check they have all stopped
    @test length(get_containers(jt1_image, args=["--all"])) == 0

    # Delete repo
    delete_ecr_repo(jt1_repo)
    # Check it's deleted
    @test isnothing(Jot.get_ecr_repo(jt1_image))

    # Delete image
    jt1_repository = jt1_image.repository
    delete_image(jt1_image, force=true)
    # Check it's deleted
    @test isnothing(Jot.get_image(jt1_repository))

    # Delete role
    delete_aws_role(jt1_role)
    # Check it's deleted
    @test isnothing(Jot.get_aws_role(jt1_role_name))

  end
end

  
