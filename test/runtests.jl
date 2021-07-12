using Test
using Pkg
using Random

const jot_path = abspath(joinpath(pwd(), ".."))
Pkg.develop(PackageSpec(path=jot_path))
using Jot

Pkg.develop(PackageSpec(path=joinpath(jot_path, "test", "JotTest1")))
using JotTest1

const aws_config = AWSConfig(account_id="513118378795", region="ap-northeast-1")
const test_suffix = randstring("abcdefghijklmnopqrstuvwxyz1234567890", 12)

function reset_jt1_response_suffix()::String
  response_suffix = randstring(12)
  open(joinpath(jot_path, "test/JotTest1/response_suffix"), "w") do rsfile
    write(rsfile, response_suffix)
  end
  response_suffix
end

function get_jt1_response_suffix()::String
  open(joinpath(jot_path, "test/JotTest1/response_suffix"), "r") do rsfile
    readchomp(rsfile, String)
  end
end

function run_tests(; 
    to::AbstractString="lambda_function", 
    package_compile::Bool=false, 
    clean::String="true",
    example_only::Bool=false,
  )
  if example_only
    test_documentation_example()
    return
  end
  package_compile = package_compile == "true" ? true : false
  clean = clean == "true" ? true : false
  rs_suffix = reset_jt1_response_suffix()

  responder_inputs = [
    ((JotTest1, :response_func, Dict), Dict{Symbol, String}()),
    ((PackageSpec(path=joinpath(jot_path, "./test/JotTest1")), :response_func, Dict), Dict{Symbol, String}()),
    ((joinpath(jot_path, "./test/JotTest2/response_func.jl"), :response_func, Vector{Float64}), Dict(:dependencies => ["SpecialFunctions"])),
    (("https://github.com/harris-chris/JotTest3", :response_func, Vector{Float64}), Dict{Symbol, String}()),
  ]

  responders = @testset "Test Responder" begin 
    return [test_responder(args...; kwargs...) for (args, kwags) in responder_inputs]
  end
  if to == "responder"
    clean && clean_up()
    return
  end

  test_data = [
    (Dict("double" => 4.5), 9.0, [1,2]),
    (Dict("add suffix" => "test-"), "test-"*get_jt1_response_suffix(), [1,2]),
    ([1, 2, 3, 4], Vector{Float64}([0.0, 0.0, 0.6931471805599453, 1.791759469228055]), Dict("this" => "that")),
    ([1, 2, 3, 4], Vector{Float64}([1.0, 1.0, 2.0, 6.0]), "string arg"),
  ]

  local_image_inputs = [
    (res[1], 1, false, true),
    (res[2], 2, true, false),
    (res[3], 3, false, false),
    (res[4], 4, false, false),
  ]

  local_images = @testset "Local Images" begin
    return [test_local_image(li_input..., datum[1], datum[2]) for (li_input, datum) in zip(local_image_inputs, test_data)]
  end
  
  if to == "local_image"
    clean && clean_up()
    return
  end

  test_package_compile(local_images[2], local_images[1])
  if to == "package_compiler"
    clean && clean_up()
    return
  end

  # Randomly select one of our lambdas
  use_num = rand(1:length(responders))
  (ecr_repo, remote_image) = test_ecr_repo(responders[use_num], local_images[use_num])
  if to == "ecr_repo"
    clean && clean_up()
    return
  end

  aws_role = test_aws_role()
  if to == "aws_role"
    clean && clean_up()
    return
  end

  lambda_function = test_lambda_function(ecr_repo, remote_image, aws_role, test_data[use_num]...)
  if to == "lambda_function"
    clean && clean_up()
    return
  end
  clean && clean_up()
end

function test_documentation_example()
  @testset "Documentation example" begin
    # Create a simple script to use as a lambda function
    open("increment_vector.jl", "w") do f
      write(f, "increment_vector(v::Vector{Int}) = map(x -> x + 1, v)")
    end

    # Turn it into a Responder; this specifies the function we will create a Lambda from
    increment_responder = get_responder("./increment_vector.jl", :increment_vector, Vector{Int})

    # Create a local docker image from the responder
    local_image = create_local_image("increment-vector", increment_responder)

    # Push this local docker image to AWS ECR; create an AWS role that can execute it
    (ecr_repo, remote_image) = push_to_ecr!(local_image)
    aws_role = create_aws_role("increment-vector-role")
     
    # Create a lambda function from this remote_image... 
    increment_vector_lambda = create_lambda_function(remote_image, aws_role)

    # ... and test it to see if it's working OK
    @test run_test(increment_vector_lambda, [2,3,4], [3,4,5]; check_function_state=true) |> first

    # Clean up 
    delete!(increment_vector_lambda)
    delete!(ecr_repo)
    delete!(aws_role)
    delete!(local_image)
    rm("./increment_vector.jl")
  end
end

function test_responder(
    res_obj::Any,
    res_func::Symbol,
    res_type::Type{IT},
  )::AbstractResponder
  this_res = get_responder(res_obj, res_func, IT)
  @test isa(Jot.get_tree_hash(this_res), String)
  @test isa(Jot.get_commit(this_res), String)
  this_res
end

function test_responder(
    jt1_rf_check::Function,
  )::Tuple{AbstractResponder, AbstractResponder, AbstractResponder}
  jt1_pkg = PackageSpec(path=joinpath(jot_path, "./test/JotTest1"))
  jt1_res = get_responder(jt1_pkg, :response_func, Dict)
  # Create an altered responder and check that the two do not match
  @testset "Test original JT1 responder" begin
    @test jt1_rf_check(Dict("add suffix" => "t")) == JotTest1.response_func(Dict("add suffix" => "t"))
    @test jt1_rf_check(Dict("double" => 2.4)) == JotTest1.response_func(Dict("double" => 2.4))
    @test isa(Jot.get_tree_hash(jt1_res), String)
    @test isa(Jot.get_commit(jt1_res), String)
  end
  _ = reset_jt1_response_suffix()
  jt1_alt_res = get_responder(jt1_pkg, :response_func, Dict)
  @testset "Test responder" begin
    @test jt1_rf_check(Dict("add suffix" => "t")) != JotTest1.response_func(Dict("add suffix" => "t"))
    @test jt1_res != jt1_alt_res 
  end
  jt2_res = get_responder(joinpath(jot_path, "./test/JotTest2/response_func.jl"), 
                      :response_func, 
                      Vector{Float64}; 
                      dependencies=["SpecialFunctions"])
  jt3_res = get_responder("./test/JotTest2/response_func.jl", 
                      :response_func, 
                      Vector{Float64})
  (jt1_res, jt1_alt_res, jt2_res)
end

function test_local_image(
    res::AbstractResponder, 
    num::Int64,
    use_config::Bool,
    package_compile::Bool,
    test_request::Any,
    expected::Any,
  )::LocalImage
  local_image = create_local_image("jt$(num)-local-"*test_suffix, 
                                   res; 
                                   aws_config = use_config ? aws_config : nothing, 
                                   package_compile = package_compile)
  @test Jot.matches(res, local_image)
  # Test that container runs
  cont = run_image_locally(local_image)
  @test is_container_running(cont)
  conts = get_all_containers(local_image)
  @test length(conts) == 1
  foreach(stop_container, conts)
  # Check containers have stopped
  @test length(get_all_containers(local_image)) == 0
  # Run local test of container, without value
  @test run_test(local_image) |> first
  # Run local test of container, with expected response
  @test run_test(local_image, test_request, expected) |> first

  package_compile && @test jt1_time < (jt2_time / 2)
  return local_image
end

function test_package_compile(
    li_uncompiled::LocalImage,
    li_compiled::LocalImage,
  )
  (_, uncompiled_time) = run_test(li_uncompiled)
  (_, compiled_time) = run_test(li_compiled)
  @testset "Package compiler" begin
    @test compiled_time < (uncompiled_time / 2)
  end
end

function test_ecr_repo(res::AbstractResponder, local_image::LocalImage)::Tuple{ECRRepo, RemoteImage}
  (ecr_repo, remote_image) = push_to_ecr!(local_image)
  @testset "Test remote image" begin 
    @test Jot.matches(local_image, ecr_repo)
    # Check we can find the repo
    @test !isnothing(Jot.get_ecr_repo(local_image))
    # Check that we can find the remote image which matches our local image
    ri_check = Jot.get_remote_image(local_image)
    @test !isnothing(ri_check)
    @test Jot.matches(local_image, remote_image)
    @test Jot.matches(res, remote_image)
  end
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
    test_request::Any,
    expected::Any,
    exception_request::Any,
  )::LambdaFunction
  lambda_function = create_lambda_function(ecr_repo, aws_role)
  @testset "Lambda Function test" begin
    @test Jot.matches(remote_image, lambda_function)
    # Check that we can find it
    @test lambda_function in Jot.get_all_lambda_functions()
    # Invoke it 
    response = invoke_function(test_request, lambda_function; check_state=true)
    @test response == expected
    # Create the same thing using a remote image
    @test lambda_function == create_lambda_function(
      remote_image, aws_role; function_name="addl"*test_suffix
    )
    @test_throws LambdaException invoke_function(exception_request, lambda_function; check_state=true)
  end
  lambda_function
end

function clean_up()
  # Clean up
  # TODO clean up based on lambdas, eventually
  @show "running clean up"
  @testset "Clean up" begin
    test_lfs = [x for x in Jot.get_all_lambda_functions() if occursin(test_suffix, x.FunctionName)]
    test_repos = [x for x in Jot.get_all_ecr_repos() if occursin(test_suffix, x.repositoryName)]
    @debug test_suffix
    @debug x.repositoryName
    @debug test_repos
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

@testset "All Tests" begin
  test_args = Dict(key => val for (key, val) in map(x -> split(x, '='), ARGS))
  test_args = Dict(Symbol(key) => (val in ["true", "false"] ? Meta.parse(val) : val) for (key, val) in test_args)
  run_tests(;test_args...)
end

