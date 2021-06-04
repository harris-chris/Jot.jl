module JotTest1

function response_func(s::String)::String
  @debug pwd()
  this_path = Base.moduleroot(JotTest1) |> pathof
  open(joinpath(this_path, "response_suffix"), "r") do rs
    response_suffix = readchomp(rs)
    s * response_suffix
  end
end

end # module
