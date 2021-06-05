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
  config = Config(
                  AWSConfig(account_id="513118378795", region="ap-northeast-1"),
                  ImageConfig(name="jot-test-1"),
                  LambdaFunctionConfig(name="jot-test-1"),
                 )
  jt1_def = Definition(JotTest1, "response_func", config, ("test", "test" * response_suffix))
  jt1_image = build_image(jt1_def)
  # Test that container runs
  jt1_cont = run_image_locally(jt1_image)
  @test Jot.is_container_running(jt1_cont)
  jt1_conts = Jot.get_containers(jt1_image)
  @test length(jt1_conts) == 1
  for cont in jt1_conts
    stop_container(cont)
  end
  # Check container has stopped
  @test length(Jot.get_containers(jt1_image)) == 0
  # Run local test of container
  @test run_local_test(jt1_image, jt1_def.test...)
  
end
