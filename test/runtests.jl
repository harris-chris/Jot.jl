using Test
using Pkg
using Random

# We want to add the two test packages to the global user environment; this way
# they are available for the tests, but are not included in Jot's Project.toml
const jot_path = abspath(joinpath(pwd(), ".."))
Pkg.activate()
Pkg.develop(PackageSpec(path=joinpath(jot_path, "test", "JotTest1")))
using JotTest1
Pkg.develop(PackageSpec(path=joinpath(jot_path, "test", "JotTest2")))
using JotTest2

# Now switch back to the Jot project
Pkg.activate(jot_path)
using Jot

const aws_config = AWSConfig(account_id="513118378795", region="ap-northeast-1")
const test_suffix = randstring("abcdefghijklmnopqrstuvwxyz1234567890", 12)
const jot_multi_test_tag_key = "JOT_MULTI_TEST_NUM"

@enum MultiTo begin
  responder = 1
  local_image = 2
  ecr_repo = 3
  lambda_function = 4
  package_compiler_local = 5
  package_compiler_lambda = 6
  to_end = 1000
end

function continue_tests(
    multi_to::MultiTo,
    up_to::MultiTo,
  )::Bool
  Int(up_to) <= Int(multi_to)
end

function reset_response_suffix(test_path::String)::String
  response_suffix = randstring(12)
  open(joinpath(jot_path, test_path), "w") do rsfile
    write(rsfile, response_suffix)
  end
  response_suffix
end

function get_response_suffix(test_path::String)::String
  open(joinpath(jot_path, test_path), "r") do rsfile
    readchomp(rsfile)
  end
end

struct ExpectedLabels
  RESPONDER_PACKAGE_NAME::Union{Nothing, String}
  RESPONDER_FUNCTION_NAME::String
  RESPONDER_PKG_SOURCE::String
  user_defined_labels::Dict{String, String}
end

function test_actual_labels_against_expected(
    actual::Jot.Labels,
    expected::ExpectedLabels,
  )::Bool
  @info [getfield(actual, fn) for fn in fieldnames(ExpectedLabels) if !isnothing(getfield(expected, fn))]
  @info [getfield(expected, fn) for fn in fieldnames(ExpectedLabels) if !isnothing(getfield(expected, fn))]
  all([getfield(actual, fn) == getfield(expected, fn) for fn in fieldnames(ExpectedLabels)])
end

function run_tests(
    example_simple::Bool,
    example_components::Bool,
    multi_tests_list::Union{Nothing, Vector{Int64}},
    compile_tests_list::Union{Nothing, Vector{Int64}},
    multi_tests_to::MultiTo,
    clean_up::Bool,
    clean_up_only::Bool,
    run_all::Bool,
  )
  if run_all
    example_simple = true
    example_components = true
    multi_tests_list = Vector{Int64}()
    compile_tests_list = Vector{Int64}()
    clean_up = true
  end

  if clean_up_only
    if any([example_simple, example_components, !isnothing(multi_tests_list)])
      error("--clean-up-only passed but tests also passed")
    else
      clean_up_example_simple_test()
      clean_up_multi_tests()
    end
  else
    ENV["JOT_TEST_RUNNING"] = "true"
    example_simple && run_example_simple_test(clean_up)
    example_components && run_example_components_test(clean_up)
    if !isnothing(multi_tests_list) && !isnothing(compile_tests_list)
      multi_tests_list = unique([multi_tests_list; compile_tests_list])
    end
    compile_tests_list = if isnothing(compile_tests_list)
      Vector{Int64}()
      else compile_tests_list end
    !isnothing(multi_tests_list) && run_multi_tests(
      multi_tests_list, compile_tests_list, multi_tests_to, clean_up
    )
    ENV["JOT_TEST_RUNNING"] = "false"
  end
end

function run_example_components_test(clean_up::Bool)
  @testset "Example components" begin
    # Create a simple script to use as a lambda function
    open("increment_vector.jl", "w") do f
      write(f, "increment_vector(v::Vector{Int}) = map(x -> x + 1, v)")
    end

    # Turn it into a Responder; this specifies the function we will create a Lambda from
    @info "Creating responder"
    increment_responder = get_responder("./increment_vector.jl", :increment_vector, Vector{Int})

    # Create a LambdaComponents instance from the responder
    @info "Creating LambdaComponents"
    lambda_components = create_lambda_components(
      increment_responder; image_suffix="increment-vector"
    )

    lambda_components |> with_remote_image! |> with_lambda_function! |> run_test
    if clean_up
      clean_up_lambda_components(lambda_components)
    end
  end
  # Finally, run this in case clean-up has failed
  clean_up_example_simple_test()
end

function clean_up_lambda_components(lambda_components::LambdaComponents)
  delete!(lambda_components)
  rm("./increment_vector.jl")

  @test isnothing(get_local_image("increment-vector"))
  @test isnothing(get_aws_role(lambda_components.lambda_function.Role))
  @test isnothing(get_remote_image("increment-vector"))
end

function run_example_simple_test(clean_up::Bool)
  @testset "Example simple" begin
    # Create a simple script to use as a lambda function
    open("increment_vector.jl", "w") do f
      write(f, "increment_vector(v::Vector{Int}) = map(x -> x + 1, v)")
    end

    # Turn it into a Responder; this specifies the function we will create a Lambda from
    @info "Creating responder"
    increment_responder = get_responder("./increment_vector.jl", :increment_vector, Vector{Int})

    # Create a local docker image from the responder
    @info "Creating local image"
    local_image = create_local_image(increment_responder; image_suffix="increment-vector")
    @test get_local_image("increment-vector") == local_image
    @test get_lambda_name(local_image) == "increment-vector"

    # Push this local docker image to AWS ECR
    @info "Creating remote image"
    remote_image = push_to_ecr!(local_image)
    @test get_remote_image("increment-vector") == remote_image
    @test get_lambda_name(remote_image) == "increment-vector"

    # Create a lambda function from this remote_image...
    @info "Creating lambda function"
    increment_vector_lambda = create_lambda_function(remote_image)
    @test get_lambda_function("increment-vector") == increment_vector_lambda
    @test get_lambda_name(increment_vector_lambda) == "increment-vector"

    # ... and test it to see if it's working OK
    @info "Testing lambda function"
    @test run_lambda_function_test(
      increment_vector_lambda, [2,3,4], [3,4,5]; check_function_state=true
    ) |> first
  end
  if clean_up
    clean_up_example_simple_test()
  end
end

function clean_up_example_simple_test()
  @testset "Clean up example simple test" begin
    while true
      existing_ri = get_lambda_function("increment-vector")
      if isnothing(existing_ri) break
      else delete!(existing_ri) end
    end
    @test isnothing(get_lambda_function("increment-vector"))

    while true
      existing_ri = get_remote_image("increment-vector")
      if isnothing(existing_ri) break
      else delete!(existing_ri) end
    end
    @test isnothing(get_remote_image("increment-vector"))

    while true
      existing_ecr = get_ecr_repo("increment-vector")
      if isnothing(existing_ecr) break
      else delete!(existing_ecr) end
    end
    @test isnothing(get_ecr_repo("increment-vector"))

    while true
      @info "Starting to delete local images"
      existing_li = get_local_image("increment-vector")
      @show existing_li
      if isnothing(existing_li) break
      else delete!(existing_li) end
    end
    @test isnothing(get_local_image("increment-vector"))
  end
end

struct GetResponderArgs
  responder_obj::Union{String, Module}
  responder_func::Symbol
  responder_param_type::Type
  kwargs::Dict{Symbol, Any}
end

struct ResponderFunctionTestArgs
  good_arg::Any
  expected_response::Any
  invalid_arg::Any
end

function to_function_test_data(
    ta::ResponderFunctionTestArgs,
  )::FunctionTestData
  FunctionTestData(
    ta.good_arg,
    ta.expected_response,
  )
end

struct CreateLocalImageArgs
  use_aws_config::Bool
  expected_labels::ExpectedLabels
  use_function_test_data::Bool
  image_suffix::Union{Nothing, String}
  image_tag::Union{Nothing, String}
end

mutable struct TestState
  responder::Union{Nothing, AbstractResponder}
  local_image::Union{Nothing, LocalImage}
  compiled_local_image::Union{Nothing, LocalImage}
  ecr_repo::Union{Nothing, ECRRepo}
  remote_image::Union{Nothing, RemoteImage}
  compiled_remote_image::Union{Nothing, RemoteImage}
  lambda_function::Union{Nothing, LambdaFunction}
  compiled_lambda_function::Union{Nothing, LambdaFunction}
end

get_empty_test_state() = TestState(
  nothing, nothing, nothing, nothing, nothing, nothing, nothing, nothing
)

mutable struct SingleTestData
  get_responder_args::GetResponderArgs
  responder_function_test_args::ResponderFunctionTestArgs
  create_local_image_args::CreateLocalImageArgs
  test_state::TestState
end

function get_multi_tests_data()::Vector{SingleTestData}

  reset_response_suffix("test/JotTest1/response_suffix")
  reset_response_suffix("test/JotTest2/response_suffix")

  multi_test_1_data = SingleTestData(
    GetResponderArgs(
      JotTest1,
      :response_func,
      Dict,
      Dict{Symbol, Any}(),
    ),
    ResponderFunctionTestArgs(
      Dict("double" => 4.5), 9.0, [1,2]
    ),
    CreateLocalImageArgs(
      false,
      ExpectedLabels(
        "JotTest1",
        "response_func",
        joinpath(jot_path, "test/JotTest1"),
        Dict(jot_multi_test_tag_key=>"1"),
      ),
      true,
      "UpperCaseSuffix",
      "latest"
    ),
    get_empty_test_state(),
  )

  multi_test_2_data = SingleTestData(
    GetResponderArgs(
      JotTest2,
      :response_func,
      Dict,
      Dict(Symbol("registry_urls") => ["https://github.com/NREL/JuliaRegistry.git"]),
    ),
    ResponderFunctionTestArgs(
      Dict("add suffix" => "test-"),
      "test-"*get_response_suffix("test/JotTest2/response_suffix"),
      [1,2],
    ),
    CreateLocalImageArgs(
      true,
      ExpectedLabels(
        "JotTest2",
        "response_func",
        joinpath(jot_path, "test/JotTest2"),
        Dict(jot_multi_test_tag_key=>"2"),
      ),
      false,
      nothing,
      "UpperCaseTag"
    ),
    get_empty_test_state(),
  )

  multi_test_3_data = SingleTestData(
    GetResponderArgs(
      "https://github.com/harris-chris/JotTest3",
      :response_func,
      Vector{Float64},
      Dict{Symbol, Any}(),
    ),
    ResponderFunctionTestArgs(
      [1, 2, 3, 4], Vector{Float64}([1.0, 1.0, 2.0, 6.0]), "string arg",
    ),
    CreateLocalImageArgs(
      false,
      ExpectedLabels(
        "JotTest3",
        "response_func",
        "https://github.com/harris-chris/JotTest3",
        Dict(jot_multi_test_tag_key=>"3"),
      ),
      true,
      nothing,
      "latest"
    ),
    get_empty_test_state(),
  )

  multi_test_4_data = SingleTestData(
    GetResponderArgs(
      joinpath(jot_path, "test/JotTest4/jot-test-4.jl"),
      :map_log_gamma,
      Vector{Float64},
      Dict(
        Symbol("dependencies") => ["SpecialFunctions"],
        Symbol("registry_urls") => ["https://github.com/NREL/JuliaRegistry.git"],
      )
    ),
    ResponderFunctionTestArgs(
      [1, 2, 3, 4],
      Vector{Float64}([0.0, 0.0, 0.6931471805599453, 1.791759469228055]),
      Dict("this" => "that"),
    ),
    CreateLocalImageArgs(
      false,
      ExpectedLabels(
        Jot.get_package_name_from_script_name("jot-test-4.jl"),
        "map_log_gamma",
        joinpath(jot_path, "test/JotTest4/jot-test-4.jl"),
        Dict(jot_multi_test_tag_key=>"4"),
      ),
      false,
      nothing,
      "latest"
    ),
    get_empty_test_state(),
  )

  multi_test_5_arg = randstring(8)
  multi_test_5_data = SingleTestData(
    GetResponderArgs(
      joinpath(jot_path, "test/JotTest5/jot-test-5.jl"),
      :use_scratch_space,
      String,
      Dict(
        Symbol("dependencies") => ["Scratch"],
      )
    ),
    ResponderFunctionTestArgs(
      multi_test_5_arg,
      "read: " * multi_test_5_arg,
      1,
    ),
    CreateLocalImageArgs(
      false,
      ExpectedLabels(
        Jot.get_package_name_from_script_name("jot-test-5.jl"),
        "use_scratch_space",
        joinpath(jot_path, "test/JotTest5/jot-test-5.jl"),
        Dict(jot_multi_test_tag_key=>"5"),
      ),
      true,
      nothing,
      "latest"
    ),
    get_empty_test_state(),
  )

  [
    multi_test_1_data,
    multi_test_2_data,
    multi_test_3_data,
    multi_test_4_data,
    multi_test_5_data,
  ]
end

function run_multi_tests(
    test_list::Vector{Int64},
    compile_list::Vector{Int64},
    multi_to::MultiTo,
    clean_up::Bool
  )
  tests_data_all = get_multi_tests_data()
  test_list = if isempty(test_list)
    test_list = [i for (i, _) in enumerate(tests_data_all)]
  else test_list end
  tests_data = tests_data_all[test_list]

  aws_role = test_aws_role()

  @testset "Multi-Tests" begin
    foreach(zip(test_list, tests_data)) do (i, test_data)
      @testset "Multi-Tests Test $i" begin
        if continue_tests(multi_to, responder)
          @testset "Responder test" begin
            test_data.test_state.responder = test_responder(
              test_data.get_responder_args.responder_obj,
              test_data.get_responder_args.responder_func,
              test_data.get_responder_args.responder_param_type,
              test_data.get_responder_args.kwargs,
            )
          end
        end

        if continue_tests(multi_to, local_image)
          if test_data.test_state.responder != nothing
            @testset "Local image test" begin
              test_data.test_state.local_image = test_local_image(
                test_data.test_state.responder,
                test_data.create_local_image_args,
                test_data.responder_function_test_args,
              )
            end
          else
            @info "RESPONDER NOT FOUND, SKIPPING LOCAL IMAGE TEST"
          end
        end

        if continue_tests(multi_to, ecr_repo)
          if test_data.test_state.local_image != nothing
            @testset "Remote image test" begin
              (ecr_repo, remote_image) = test_ecr_repo(
                test_data.test_state.responder,
                test_data.test_state.local_image,
                test_data.create_local_image_args.expected_labels,
              )
              test_data.test_state.ecr_repo = ecr_repo
              test_data.test_state.remote_image = remote_image
            end
          else
            @info "LOCAL IMAGE NOT FOUND, SKIPPING REMOTE IMAGE TEST"
          end
        end

        if continue_tests(multi_to, lambda_function)
          if isnothing(test_data.test_state.remote_image)
            @info "REMOTE IMAGE NOT FOUND, SKIPPING LAMBDA FUNCTION TEST"
          else
            skip_test_because_running_comparison_test_later = (
              i in compile_list && continue_tests(multi_to, package_compiler_lambda)
            )
            @testset "Lambda Function test" begin
              test_data.test_state.lambda_function = test_lambda_function(
                test_data.test_state.ecr_repo,
                test_data.test_state.remote_image,
                aws_role,
                test_data.responder_function_test_args,
                skip_test_because_running_comparison_test_later,
              )
            end
          end
        end

        if continue_tests(multi_to, package_compiler_local)
          if !(i in compile_list)
            @info "--compile NOT SET FOR $i, SKIPPING LOCAL PACKAGE COMPILE TEST"
          elseif isnothing(test_data.test_state.responder)
            @info "RESPONDER NOT FOUND, SKIPPING PACKAGE COMPILE TEST"
          elseif isnothing(test_data.test_state.local_image)
            @info "LOCAL IMAGE NOT FOUND, SKIPPING PACKAGE COMPILE TEST"
          else
            @testset "Package compiler local test" begin
              test_data.test_state.compiled_local_image = test_compiled_local_image(
                test_data.test_state.responder,
                test_data.create_local_image_args,
                test_data.responder_function_test_args,
                test_data.test_state.local_image,
              )
            end
          end
        end

        if continue_tests(multi_to, package_compiler_lambda)
          if !(i in compile_list)
            @info "--compile NOT SET FOR $i, SKIPPING LAMBDA PACKAGE COMPILE TEST"
          elseif isnothing(test_data.test_state.responder)
            @info "RESPONDER NOT FOUND, SKIPPING PACKAGE COMPILE TEST"
          elseif isnothing(test_data.test_state.lambda_function)
            @info "LAMBDA FUNCTION NOT FOUND, SKIPPING PACKAGE COMPILE TEST"
          else
            @testset "Package compiler lambda function test" begin
              test_data.test_state.compiled_lambda_function = test_compiled_lambda_function(
                test_data.test_state.compiled_local_image,
                aws_role,
                test_data.responder_function_test_args,
                test_data.test_state.lambda_function,
              )
            end
          end
        end
      end
    end
  clean_up && clean_up_multi_tests()
  end
end

function test_responder(
    res_obj::Union{String, Module},
    res_func::Symbol,
    res_type::Type{IT},
    kwargs::Dict{Symbol, Any},
  )::AbstractResponder{IT} where {IT}
  this_res = get_responder(
    res_obj, res_func, IT; kwargs...
  )
  @test isa(Jot.get_tree_hash(this_res), String)
  @test isa(Jot.get_commit(this_res), String)
  this_res
end

function test_local_image(
    res::AbstractResponder,
    create_local_image_args::CreateLocalImageArgs,
    responder_function_test_args::ResponderFunctionTestArgs,
  )::LocalImage
  function_test_data = if create_local_image_args.use_function_test_data
    to_function_test_data(responder_function_test_args)
  else
    nothing
  end
  local_image = create_local_image(
    res;
    aws_config = create_local_image_args.use_aws_config ? aws_config : nothing,
    function_test_data = function_test_data,
    user_defined_labels = create_local_image_args.expected_labels.user_defined_labels,
    image_suffix = create_local_image_args.image_suffix,
    image_tag = create_local_image_args.image_tag,
  )
  @test Jot.matches(res, local_image)
  @test Jot.is_jot_generated(local_image)
  @test test_actual_labels_against_expected(
    get_labels(local_image), create_local_image_args.expected_labels
  )
  # Test that container runs
  cont = run_image_locally(local_image)
  @test is_container_running(cont)
  conts = get_all_containers(local_image)
  @test length(conts) == 1
  foreach(stop_container, conts)
  # Check containers have stopped
  @test length(get_all_containers(local_image)) == 0
  # Run local test of container, without value
  @test run_local_image_test(local_image) |> first
  # Run local test of container, with expected response
  @test run_local_image_test(
    local_image,
    responder_function_test_args.good_arg,
    responder_function_test_args.expected_response;
    then_stop=true
  ) |> first
  sleep(1)
  local_image
end

function compare_local_image_test_times(
    compiled::LocalImage,
    uncompiled::LocalImage,
    test_arg::Any,
    expected_response::Any,
    repeat_num::Int64,
  )::Tuple{Float64, Float64}
  total_run_time = 0.0
  for num = 1:repeat_num
    _, this_run_time = run_local_image_test(compiled, test_arg, expected_response)
    @info "Test run $num with compiled local image took $this_run_time"
    total_run_time += this_run_time
  end
  average_compiled_run_time = total_run_time / repeat_num
  @info "Average compiled run time was $average_compiled_run_time"
  total_run_time = 0.0
  for num = 1:repeat_num
    _, this_run_time = run_local_image_test(uncompiled, test_arg, expected_response)
    @info "Test run $num with uncompiled local image took $this_run_time"
    total_run_time += this_run_time
  end
  average_uncompiled_run_time = total_run_time / repeat_num
  @info "Average uncompiled run time was $average_uncompiled_run_time"
  return (average_compiled_run_time, average_uncompiled_run_time)
end

function compare_lambda_function_test_times(
    compiled::LambdaFunction,
    uncompiled::LambdaFunction,
    test_arg::Any,
    expected_response::Any,
    repeat_num::Int64,
  )::Tuple{Float64, Float64}
  total_run_time = 0.0
  # Throw away first result, it's unrepresentative
  _, _ = run_lambda_function_test(compiled, test_arg, expected_response)
  for num = 1:repeat_num
    _, test_log = run_lambda_function_test(compiled, test_arg, expected_response)
    this_run_time = get_invocation_run_time(test_log)
    @info "Test run $num with compiled local image took $this_run_time"
    total_run_time += this_run_time
  end
  average_compiled_run_time = total_run_time / repeat_num
  @info "Average compiled run time was $average_compiled_run_time"
  total_run_time = 0.0
  # Throw away first result, it's unrepresentative
  _, _ = run_lambda_function_test(uncompiled, test_arg, expected_response)
  for num = 1:repeat_num
    _, test_log = run_lambda_function_test(uncompiled, test_arg, expected_response)
    this_run_time = get_invocation_run_time(test_log)
    @info "Test run $num with uncompiled local image took $this_run_time"
    total_run_time += this_run_time
  end
  average_uncompiled_run_time = total_run_time / repeat_num
  @info "Average uncompiled run time was $average_uncompiled_run_time"
  return (average_compiled_run_time, average_uncompiled_run_time)
end

function test_compiled_local_image(
    res::AbstractResponder,
    create_local_image_args::CreateLocalImageArgs,
    responder_function_test_args::ResponderFunctionTestArgs,
    uncompiled_local_image::LocalImage;
    repeat_num::Int64 = 5,
  )::LocalImage
  function_test_data = to_function_test_data(responder_function_test_args)
  compiled_local_image = create_local_image(
    res;
    aws_config = create_local_image_args.use_aws_config ? aws_config : nothing,
    function_test_data = function_test_data,
    package_compile = true,
    user_defined_labels = create_local_image_args.expected_labels.user_defined_labels,
    image_suffix = create_local_image_args.image_suffix,
    image_tag = create_local_image_args.image_tag,
  )
  (average_compiled_run_time, average_uncompiled_run_time) = compare_local_image_test_times(
    compiled_local_image,
    uncompiled_local_image,
    responder_function_test_args.good_arg,
    responder_function_test_args.expected_response,
    repeat_num,
  )
  @test average_compiled_run_time < (average_uncompiled_run_time / 2)
  compiled_local_image
end

function test_ecr_repo(
    res::AbstractResponder,
    local_image::LocalImage,
    expected_labels::ExpectedLabels,
  )::Tuple{ECRRepo, RemoteImage}
  remote_image = push_to_ecr!(local_image)
  ecr_repo = remote_image.ecr_repo
  @test Jot.matches(local_image, ecr_repo)
  @test Jot.is_jot_generated(remote_image)
  @test test_actual_labels_against_expected(get_labels(ecr_repo), expected_labels)
  # Check we can find the repo
  @test !isnothing(Jot.get_ecr_repo(local_image))
  # Check that we can find the remote image which matches our local image
  ri_check = Jot.get_remote_image(local_image)
  @test !isnothing(ri_check)
  @test Jot.matches(local_image, remote_image)
  @test Jot.matches(res, remote_image)
  (ecr_repo, remote_image)
end

function test_aws_role()::AWSRole
  aws_role =  create_aws_role("jot-test-role-"*test_suffix)
  @testset "Test AWS role" begin
    @test aws_role in get_all_aws_roles()
  end
  aws_role
end

function test_lambda_function(
    ecr_repo::ECRRepo,
    remote_image::RemoteImage,
    aws_role::AWSRole,
    responder_function_test_args::ResponderFunctionTestArgs,
    skip_test::Bool,
  )::LambdaFunction
  lambda_function = create_lambda_function(remote_image; role = aws_role)
  @test Jot.is_jot_generated(lambda_function)
  @test Jot.matches(remote_image, lambda_function)
  # Check that we can find it
  @test lambda_function in Jot.get_all_lambda_functions()
  if !skip_test
    # Invoke it
    (result, log) = run_lambda_function_test(
      lambda_function,
      responder_function_test_args.good_arg,
      responder_function_test_args.expected_response;
      check_function_state=true
    )
    @test result
    @info "Lambda function ran in $(get_invocation_run_time(log))"
    # Create the same thing using a remote image
    @test lambda_function == create_lambda_function(
      remote_image;
      role = aws_role,
      function_name = "addl" * ecr_repo.repositoryName
    )
    @test_throws LambdaException invoke_function(
      responder_function_test_args.invalid_arg, lambda_function; check_state=true
    )
  end
  lambda_function
end

function test_compiled_lambda_function(
    compiled_local_image::LocalImage,
    aws_role::AWSRole,
    responder_function_test_args::ResponderFunctionTestArgs,
    uncompiled_lambda_function::LambdaFunction,
    repeat_num::Int64 = 5,
  )::LambdaFunction
  remote_image = push_to_ecr!(compiled_local_image)
  ecr_repo = remote_image.ecr_repo
  compiled_lambda_function = create_lambda_function(
    remote_image; role = aws_role, function_name = "addl" * ecr_repo.repositoryName
  )
  (average_compiled_run_time, average_uncompiled_run_time) = compare_lambda_function_test_times(
    compiled_lambda_function,
    uncompiled_lambda_function,
    responder_function_test_args.good_arg,
    responder_function_test_args.expected_response,
    repeat_num,
  )
  @test average_compiled_run_time < (average_uncompiled_run_time / 2)
  compiled_lambda_function
end

function clean_up_multi_tests()
  # Clean up
  # TODO clean up based on lambdas, eventually
  @testset "Clean up multi tests" begin
    test_lfs = [x for x in Jot.get_all_lambda_functions() if occursin(test_suffix, x.FunctionName)]
    test_repos = filter(Jot.get_all_ecr_repos()) do repo
      repo_tags = Jot.get_all_tags(repo)
      jot_multi_test_tag_key in map(first, repo_tags)
    end
    @show test_repos
    test_roles = [x for x in Jot.get_all_aws_roles() if occursin(test_suffix, x.RoleName)]
    test_local_images = [x for x in Jot.get_all_local_images() if occursin(test_suffix, x.Repository)]
    test_containers = [x for img in test_local_images for x in get_all_containers(img)]

    foreach(delete!, test_lfs)
    foreach(delete!, test_repos)
    foreach(delete!, test_roles)
    foreach(x -> delete!(x, force=true), test_local_images)
    foreach(delete!, test_containers)

    @test all([!x.exists for x in test_lfs])
    @test all([!x.exists for x in test_repos])
    @test all([!x.exists for x in test_roles])
    @test all([!x.exists for x in test_local_images])
    @test all([!x.exists for x in test_containers])
  end
end

function parse_arg(val::AbstractString)
  is_bool = val in ["true", "false"]
  is_list = val[1] == '[' && val[end] == ']'
  to_parse = is_bool || is_list
  to_parse ? eval(Meta.parse(val)) : val
end

function show_help()::Nothing
  println("Run Jot.jl tests")
  println("By default no tests are run. Specify the tests to run using the following:")
  println("--example-simple to test the example on the index page of the documentation")
  println("--example-components to test the lambda components example on the index page")
  println("--multi to run all tests of the multiple test set")
  println("--multi=[1,4] to, eg, run tests 1 and 4 of the multiple test set")
  m_opts = join(instances(MultiTo), " | ")
  println("--multi-to=have the multi tests run to a specific point only")
  println("    select from $m_opts")
  println("    DEFAULT: lambda_function")
  println("--no-clean-up to have the tests skip tear down")
  println("--clean_up_only to have clean-up performed even though no tests have run")
  println("--all to run all possible tests")
end

function parse_all_flag(args::Vector{String})::Tuple{Bool, Vector{String}}
  ("--all" in args, args[args.!="--all"])
end

function parse_example_simple_flag(args::Vector{String})::Tuple{Bool, Vector{String}}
  ("--example-simple" in args, args[args.!="--example-simple"])
end

function parse_example_components_flag(args::Vector{String})::Tuple{Bool, Vector{String}}
  ("--example-components" in args, args[args.!="--example-components"])
end

function parse_tests_list(
    args::Vector{String},
    kwarg::String,
  )::Tuple{Union{Nothing, Vector{Int64}}, Vector{String}}
  kwarg_len = length(kwarg)
  test_args = filter(x -> length(x) >= kwarg_len && x[begin:kwarg_len] == kwarg, args)
  test_list = if length(test_args) == 1
    arg = test_args[begin]
    if length(arg) > kwarg_len
      list_str = test_args[end][kwarg_len + 2:end]
      if list_str[1] == '[' && list_str[end] == ']'
        list_int = eval(Meta.parse(list_str))
	unique(list_int)
      else
        error("Could not parse {kwarg} argument $list_str as list of integers, "
              * "please use format [x,y,...]")
      end
    else
      Vector{Int64}() # Means run all tests
    end
  elseif length(test_args) > 1
    error("$kwarg has been passed as an argument more than once")
  else
    nothing
  end
  (test_list, filter(
    x -> !(length(x) >= kwarg_len && x[begin:kwarg_len] == kwarg), args)
  )
end

function parse_multi_tests_to(args::Vector{String})::Tuple{MultiTo, Vector{String}}
  multi_args = filter(x -> length(x) >= 11 && x[begin:11] == "--multi-to=", args)
  tests_to = if length(multi_args) == 1
    arg = multi_args[1]
    if Symbol(arg) in Symbol.(instances(MultiTo))
      eval(Meta.parse(arg))
    else
      valid = join(instances(MultiTo), " | ")
      error("--multi-to argument $arg is not one of $(valid)")
    end
  elseif length(multi_args) > 1
    error("--multi has been passed as an argument more than once")
  else
    to_end
  end
  (tests_to, filter(x -> !(length(x) >= 11 && x[begin:11] == "--multi-to="), args))
end

function parse_clean_up_flag(args::Vector{String})::Tuple{Bool, Vector{String}}
  (!("--no-clean-up" in args), args[args.!="--no-clean-up"])
end

function parse_clean_up_only_flag(args::Vector{String})::Tuple{Bool, Vector{String}}
  ("--clean-up-only" in args, args[args.!="--clean-up-only"])
end

if ("--help" in ARGS || length(ARGS) == 0)
  show_help()
else
  args = ARGS
  simple, args = parse_example_simple_flag(args)
  components, args = parse_example_components_flag(args)
  run_all, args = parse_all_flag(args)
  multi_list, args = parse_tests_list(args, "--multi")
  compile_list, args = parse_tests_list(args, "--compile")
  @show compile_list
  multi_to, args = parse_multi_tests_to(args)
  clean_up, args = parse_clean_up_flag(args)
  clean_up_only, args = parse_clean_up_only_flag(args)
  @show args
  if length(args) != 0
    error("Args $(join(args, ", ")) not recognized")
  end
  run_tests(
    simple, components, multi_list, compile_list, multi_to, clean_up, clean_up_only, run_all
  )
end

