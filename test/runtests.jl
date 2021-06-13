using Test
using Distributed
using Pkg
using Random

Pkg.develop(PackageSpec(path="./"))
using Jot

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

  aws_config = AWSConfig(account_id="513118378795", region="ap-northeast-1")

  test_suffix = randstring("abcdefghijklmnopqrstuvwxyz", 8)
  jt1_function = ResponseFunction(JotTest1, :response_func)
  jt1_image_name = "jot-test-1"
  jt1_image = build_image(jt1_image_name * test_suffix, jt1_function, aws_config)

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

  @testset "ECR test" begin 
    # Delete ECR repo, if it exists
    existing_repo = Jot.get_ecr_repo(jt1_image)
    isnothing(existing_repo) || delete_ecr_repo(existing_repo)

    # Create ECR repo
    create_ecr_repo(jt1_image)
    # Check we can find it
    jt1_repo = Jot.get_ecr_repo(jt1_image)
    @test !isnothing(jt1_repo)

    # Delete it
    delete_ecr_repo(jt1_repo)
    # Check it's deleted
    @test isnothing(Jot.get_ecr_repo(jt1_image))

    # Push image to ECR
    jt1_repo = push_to_ecr(jt1_image)
    # Check we can find the repo
    @test jt1_repo in Jot.get_all_ecr_repos()
    # Delete it
    delete_ecr_repo(jt1_repo)
  end

  jt1_role_name = "jt1-execution-role" * test_suffix
  @testset "AWS Role test" begin
    # Delete Test role, if it exists
    existing_role = Jot.get_aws_role(jt1_role_name)
    isnothing(existing_role) || delete_aws_role(existing_role)
    
    # Create role
    jt1_role = create_aws_role(jt1_role_name)
    # Check we can find it
    @test jt1_role == Jot.get_aws_role(jt1_role_name)
    # Verify it has execution permission
    @test Jot.aws_role_has_lambda_execution_permissions(jt1_role)

    # Delete it
    delete_aws_role(jt1_role)
    # Check it's deleted
    @test isnothing(Jot.get_aws_role(jt1_role_name))
  end

  jt1_role = create_aws_role(jt1_role_name)
  jt1_repo = create_ecr_repo(jt1_image)
  @testset "AWS Function test" begin
    # Delete Test function, if it exists
    existing_function = Jot.get_lambda_function(jt1_image_name)
    isnothing(existing_function) || delete_lambda_function(existing_function)

    # Create function
    jt1_lambda_function = create_lambda_function(jt1_repo, jt1_role)
    # Check that we can find it
    @test jt1_lambda_function == Jot.get_lambda_function(jt1_image_name)
    # Delete it
    delete_lambda_function(jt1_lambda_function)
    # Check it's deleted
    @test isnothing(Jot.get_lambda_function(jt1_image_name))
    
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
  jt1_repo = Jot.get_ecr_repo(jt1_image)
  isnothing(jt1_repo) || delete_ecr_repo(jt1_repo)
  jt1_conts = get_containers(jt1_image)
  for cont in jt1_conts
    stop_container(cont)
  end
  delete_aws_role(jt1_role)
  delete_lambda_function(jt1_lambda_function)
  delete_image(jt1_image, force=true)
end
