using Jot
using Test
using Distributed
using Pkg
using Random

@testset "Jot.jl" begin
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
  @test run_local_test(jt1_image, jt1_def.test...)
  
end
