module JotTest1

using Format

function response_func(d::Dict)
  println("JOT_OBSERVATION Starting JotTest1 response function ...")
  sleep(0.1)
  response = if haskey(d, "add suffix")
    s = d["add suffix"] |> String
    package_root = Base.moduleroot(JotTest1) |> pathof |> splitpath
    rs_path = joinpath(package_root[begin:end-2]..., "response_suffix")
    println("JOT_OBSERVATION ... reading suffix file ... ")
    sleep(0.1)
    open(rs_path, "r") do rs
      response_suffix = readchomp(rs)
      s * response_suffix
    end
  elseif haskey(d, "double")
    n = d["double"] |> Float64
    println("JOT_OBSERVATION ... multiplying ... ")
    sleep(0.1)
    n * 2
  else
    error("Input not recognized")
 end
  println("JOT_OBSERVATION ... returning from JotTest1 response function")
  response
end

end # module
