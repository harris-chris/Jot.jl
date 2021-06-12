using Test
using Distributed
using Pkg
using Random

Pkg.develop(PackageSpec(path="./"))
using Jot

@testset "Jot.jl" begin
  @testset "Local test" begin
    response_suffix = randstring(12)
    open("./test/JotTest1/response_suffix", "w") do rsfile
      write(rsfile, response_suffix)
    end
    Pkg.develop(PackageSpec(path="./test/JotTest1"))
    using JotTest1
    aws_config = AWSConfig(account_id="513118378795", region="ap-northeast-1")
    
    # Test that the function name is correctly validated
    @test_throws MethodError ResponseFunction(JotTest1, :bad_function_name)

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

  # @testset "Remote test" begin 
    # # Delete ECR repo, if it exists
    # try
      # delete_ecr_repo(jt1_image)
    # catch e
    # end

    # # Create ECR repo
    # create_ecr_repo(jt1_image)
    # # Check we can find it
    # @test does_ecr_repo_exist(jt1_image)

    # # Delete it
    # delete_ecr_repo(jt1_image)
    # # Check it's deleted
    # @test !does_ecr_repo_exist(jt1_image)

    # # Push image to ECR
    # push_to_ecr(jt1_image)

    # # Delete image
    # delete_image(jt1_image, force=true)
  # end
  
end
