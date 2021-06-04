using Jot
using Test
using Distributed
using Pkg

@testset "Jot.jl" begin
  @info pwd()
  Pkg.develop(PackageSpec(path="./test/JotTest1"))
  using JotTest1
  config = get_config("./test/JotTest1/config.json")
  jt1_def = Definition(JotTest1, "response_func", config, ("test", "test ok"))
  jt1_image = build_image(jt1_def)
  @test test_image_locally(jt1_image)
end
