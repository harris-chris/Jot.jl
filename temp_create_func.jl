# import Pkg; Pkg.add(url="https://github.com/harris-chris/Jot.jl#main")
build_path = "/home/chris/Downloads/jot_temp_test"
open("increment_vector.jl", "w") do f
  write(f, "increment_vector(v::Vector{Int}) = map(x -> x + 1, v)")
end

using Jot
increment_responder = get_responder(
  "./increment_vector.jl", :increment_vector, Vector{Int}; build_at_path=build_path
)

create_local_image(increment_responder)
