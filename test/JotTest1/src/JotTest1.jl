module JotTest1

using Format

function response_func(d::Dict)
  if haskey(d, "add suffix")
    s = d["add suffix"] |> String
    package_root = Base.moduleroot(JotTest1) |> pathof |> splitpath
    rs_path = joinpath(package_root[begin:end-2]..., "response_suffix")
    open(rs_path, "r") do rs
      response_suffix = readchomp(rs)
      return s * response_suffix
    end
  elseif haskey(d, "double")
    n = d["double"] |> Float64
    return n * 2
  else
    error("Input not recognized")
  end
end

end # module
