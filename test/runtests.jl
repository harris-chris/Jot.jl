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
  config = get_config("./test/JotTest1/config.json")
  jt1_def = Definition(JotTest1, "response_func", config, ("test", "test" * response_suffix))
  jt1_image = build_image(jt1_def)
  @test test_image_locally(jt1_image)
  # delete_image(jt1_image)
  
end
