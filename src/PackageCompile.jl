
struct FunctionTestData
  test_argument::Any
  expected_response::Any
end

# function create_sysimage(
#     responder::AbstractResponder,
#     function_test_data::FunctionTestData,
#   )::String
#   precompile_script = get_precompile_jl(responder, function_test_data)
#   mktemp() do path, f
#     create_sysimage(
#       [:Jot,. respo,

#   end


#   open(joinpath(responder.build_dir, "Dockerfile"), "w") do f
#     write(f, dockerfile)
#   end

