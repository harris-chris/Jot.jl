using Test
using Distributed
using Pkg
using Random

Pkg.develop(PackageSpec(path="./"))
using Jot

@testset "Jot.jl" begin
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
  jt1_function = ResponseFunction(JotTest1, :response_func)
  jt1_image = build_image("jot-test-1", jt1_function, aws_config)

  @testset "Local test" begin
    # Test that the function name is correctly validated

    jt1_function = ResponseFunction(JotTest1, :response_func)
    jt1_image = build_image("jot-test-1", jt1_function, aws_config)
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
    # Run local test of container
    request = randstring(4)
    expected_response = JotTest1.response_func(request)
    @test run_local_test(jt1_image, request, expected_response)
  end

  @testset "ECR test" begin 
    # Delete ECR repo, if it exists
    existing_repo = Jot.get_ecr_repo(jt1_image)
    if !isnothing(existing_repo) delete_ecr_repo(existing_repo) end

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
    ecr_repo = push_to_ecr(jt1_image)
    # Check we can find the repo
    @show ecr_repo
    @show Jot.get_all_ecr_repos()[2]
    @show ecr_repo == Jot.get_all_ecr_repos()[2]
    @test ecr_repo in Jot.get_all_ecr_repos()
  end

  jt1_role_name = "jt1-execution-role"
  @testset "AWS Role test" begin
    # Delete Test role, if it exists
    existing_role = Jot.get_aws_role(jt1_role_name)
    isnothing(existing_role) || delete_aws_role(existing_role)
    
    # Create role
  
  end
  
  # Clean up
  jt1_repo = Jot.get_ecr_repo(jt1_image)
  isnothing(jt1_repo) || delete_ecr_repo(jt1_repo)
  jt1_conts = get_containers(jt1_image)
  for cont in jt1_conts
    stop_container(cont)
  end
  delete_image(jt1_image, force=true)
end
