@enum LambdaFunctionState pending active

struct LambdaException <: Exception
  msg::String
end

"""
    @with_kw mutable struct LambdaFunction
        FunctionName::Union{Missing, String} = missing
        FunctionArn::Union{Missing, String} = missing
        Runtime::Union{Missing, String} = missing
        Role::Union{Missing, String} = missing
        Handler::Union{Missing, String} = missing
        CodeSize::Union{Missing, Int64} = missing
        Description::Union{Missing, String} = missing
        Timeout::Union{Missing, Int64} = missing
        MemorySize::Union{Missing, Int64} = missing
        LastModified::Union{Missing, String} = missing
        CodeSha256::Union{Missing, String} = missing
        Version::Union{Missing, String} = missing
        TracingConfig::Union{Missing, Dict{String, Any}} = missing
        RevisionId::Union{Missing, String} = missing
        PackageType::Union{Missing, String} = missing
        exists::Bool = true
    end

Represents a Lambda function, hosted on AWS. Should not be instantiated directly. If `exists` is 
`true`, then the image is assumed to exit and so should be visible from utilities such as `aws 
lambda list-functions`
"""
@with_kw mutable struct LambdaFunction
  FunctionName::Union{Missing, String} = missing
  FunctionArn::Union{Missing, String} = missing
  Runtime::Union{Missing, String} = missing
  Role::Union{Missing, String} = missing
  Handler::Union{Missing, String} = missing
  CodeSize::Union{Missing, Int64} = missing
  Description::Union{Missing, String} = missing
  Timeout::Union{Missing, Int64} = missing
  MemorySize::Union{Missing, Int64} = missing
  LastModified::Union{Missing, String} = missing
  CodeSha256::Union{Missing, String} = missing
  Version::Union{Missing, String} = missing
  TracingConfig::Union{Missing, Dict{String, Any}} = missing
  RevisionId::Union{Missing, String} = missing
  PackageType::Union{Missing, String} = missing
  exists::Bool = true
end
StructTypes.StructType(::Type{LambdaFunction}) = StructTypes.Mutable()  
Base.:(==)(a::LambdaFunction, b::LambdaFunction) = (a.CodeSha256 == b.CodeSha256)

function get_all_lambda_functions()::Vector{LambdaFunction}
  all_json = readchomp(`aws lambda list-functions`)
  JSON3.read(all_json, Dict{String, Vector{LambdaFunction}})["Functions"]
end

"""
    get_lambda_function(function_name::String)::Union{Nothing, LambdaFunction}
 
Queries AWS and returns a `LambdaFunction` object, representing a Lambda Function hosted on AWS.
"""
function get_lambda_function(function_name::String)::Union{Nothing, LambdaFunction}
  all = get_all_lambda_functions()
  index = findfirst(x -> x.FunctionName == function_name, all)
  isnothing(index) ? nothing : all[index]
end

"""
    get_lambda_function(repo::ECRRepo)::Union{Nothing, LambdaFunction}
 
Queries AWS and returns a `LambdaFunction` object, representing a Lambda Function hosted on AWS. 
The Lambda function returned is based off the given `ECRRepo` instance.
"""
function get_lambda_function(repo::ECRRepo)::Union{Nothing, LambdaFunction}
  all = get_all_lambda_functions()
  index = findfirst(x -> x.FunctionName == function_name, all)
  isnothing(index) ? nothing : all[index]
end

"""
    get_remote_image(lambda_function::LambdaFunction)::RemoteImage
 
Queries AWS and returns a `RemoteImage` object, representing a docker image hosted on AWS ECR. 
The RemoteImage returned provides the code for the provided `lambda_function`.
"""
function get_remote_image(lambda_function::LambdaFunction)::RemoteImage
  remote_images = get_all_remote_images()
  index = findfirst(x -> matches(x, lambda_function), remote_images)
  isnothing(index) && error("Unable to find RemoteImage associated with LambdaFunction")
  remote_images[index]
end

"""
    delete!(func::LambdaFunction)

Deletes a Lambda function hosted on AWS. The LambdaFunction instance continues to exist, but has its
`exists` attribute set to `false`.
"""
function delete!(func::LambdaFunction)
  func.exists || error("Function does not exist")
  delete_script = get_delete_lambda_function_script(func.FunctionArn)
  output = readchomp(`bash -c $delete_script`)
  func.exists = false 
end

function get_function_state(func_name::String)::LambdaFunctionState
  state_json = readchomp(`aws lambda get-function-configuration --function-name=$func_name`)
  state_data = JSON3.read(state_json)
  if state_data["State"] == "Pending" pending
  elseif state_data["State"] == "Active" active
  end
end

function get_function_state(func::LambdaFunction)::LambdaFunctionState
  get_function_state(func.FunctionArn)
end

"""
    invoke_function(
        request::Any,
        lambda_function::LambdaFunction;
        check_state::Bool=false,
      )::Any

Invokes a Lambda function, hosted on AWS. `request` is the argument that it will be called with.
This will be automatically converted to JSON before sending, so should match the
`response_function_param_type` of the responder used to create the function.

Returns the invoked Lambda function response, or throws an error if the invoked Lambda function has 
returned an error status.

If `check_state` is `true`, the function will wait for the AWS Lambda function to become available
before sending the request. This can be useful if the Lambda function has been created within the 
last few seconds, since there is a short set-up time before it can be called.
"""
function invoke_function(
    request::Any,
    lambda_function::LambdaFunction;
    check_state::Bool=false,
  )::Any
  if check_state
    while true
      Jot.get_function_state(lambda_function) == active && break
    end
  end
  request_json = JSON3.write(request)
  outfile_path = tempname()
  invoke_script = get_invoke_lambda_function_script(lambda_function.FunctionArn, 
                                                    request_json, 
                                                    outfile_path)
  status = readchomp(`bash -c $invoke_script`) |> JSON3.read
  response = open(outfile_path, "r") do f
    read(f, String) |> JSON3.read
  end
  if haskey(status, "FunctionError")
    throw(LambdaException("$response"))
  else
    response
  end
end

