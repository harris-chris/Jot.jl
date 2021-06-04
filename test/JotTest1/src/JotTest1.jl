module JotTest1

function response_func(s::String)::String
  @debug pwd()
  package_root = Base.moduleroot(JotTest1) |> pathof |> splitpath
  rs_path = joinpath(package_root[begin:end-2]..., "response_suffix")
  open(rs_path, "r") do rs
    response_suffix = readchomp(rs)
    s * response_suffix
  end
end

end # module
