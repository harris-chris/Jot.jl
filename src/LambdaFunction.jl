@enum LambdaFunctionState Pending Active Inactive Failed

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
@with_kw mutable struct LambdaFunction <: LambdaComponent
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

"""
    get_all_lambda_functions(jot_generated_only::Bool = true)::Vector{LambdaFunction}

Returns a vector of `LambdaFunction`s, representing all AWS-hosted Lambda functions.

`jot_generated_only` specifies whether to filter for jot-generated lambda functions only.
"""
function get_all_lambda_functions(jot_generated_only::Bool = true)::Vector{LambdaFunction}
  all_json = readchomp(`aws lambda list-functions`)
  all_lfs = JSON3.read(all_json, Dict{String, Vector{LambdaFunction}})["Functions"]
  jot_generated_only ? filter(is_jot_generated, all_lfs) : all_lfs
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
function delete!(func::LambdaFunction; delete_role::Bool = true)
  func.exists || error("Function does not exist")
  delete_script = get_delete_lambda_function_script(func.FunctionArn)
  output = readchomp(`bash -c $delete_script`)
  func.exists = false
  if delete_role
    associated_role = get_aws_role(create_role_name(func.FunctionName))
    !isnothing(associated_role) && delete!(associated_role)
  end
  nothing
end

function get_function_state(func_name::String)::LambdaFunctionState
  get_state_script = get_lambda_function_status(func_name)
  state_json = readchomp(`bash -c $get_state_script`)
  state_data = JSON3.read(state_json)
  if state_data["State"] == "Pending" Pending
  elseif state_data["State"] == "Active" Active
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

Returns the invoked Lambda function response, or throws an error if the invoked Lambda function has returned an error status.

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
      Jot.get_function_state(lambda_function) == Active && break
    end
  end
  request_json = JSON3.write(request)
  outfile_path = tempname()
  invoke_script = get_invoke_lambda_function_script(
    lambda_function.FunctionArn, request_json, outfile_path, false
  )
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

"""
    invoke_function_with_log(
        request::Any,
        lambda_function::LambdaFunction;
        check_state::Bool=false,
      )::Tuple{Any, LambdaFunctionInvocationLog}

As per invoke_function, but returns a tuple of `{Any, LambdaFunctionInvocationLog}`, consisting of the result as well as log information about the invocation in the form of a `LambdaFunctionInvocationLog`.
"""
function invoke_function_with_log(
    request::Any,
    lambda_function::LambdaFunction;
    check_state::Bool=false,
  )::Tuple{Any, LambdaFunctionInvocationLog}
  if check_state
    while true
      Jot.get_function_state(lambda_function) == Active && break
    end
  end
  request_json = JSON3.write(request)
  outfile_path = tempname()
  invoke_script = get_invoke_lambda_function_script(
    lambda_function.FunctionArn, request_json, outfile_path, true
  )

  status_pipe = Pipe()
  debug_pipe = Pipe()
  process = run(
    pipeline(`bash -c $invoke_script`, stdout=status_pipe, stderr=debug_pipe)
  )
  close(status_pipe.in)
  close(debug_pipe.in)

  status = JSON3.read(String(read(status_pipe)))
  debug = String(read(debug_pipe))

  request_id = get_request_id_from_aws_debug_output(debug)
  log_group_name = get_cloudwatch_log_group_name(lambda_function)
  (start_event, end_event, report_event, log_events) = get_cloudwatch_log_events(
    log_group_name, request_id
  )

  invocation_log = LambdaFunctionInvocationLog(
    request_id,
    log_group_name,
    start_event,
    end_event,
    report_event,
    log_events,
  )

  response = open(outfile_path, "r") do f
    read(f, String) |> JSON3.read
  end
  if haskey(status, "FunctionError")
    throw(LambdaException("$response"))
  else
    (response, invocation_log)
  end
end

function get_request_id_from_aws_debug_output(
    debug_output::AbstractString,
  )::String
  request_id_idx = findlast("RequestId: ", debug_output)
  request_id_start = last(request_id_idx) + 1
  request_id_block = debug_output[request_id_start:end]
  strip(split(request_id_block, " ")[begin])
end

function get_cloudwatch_log_group_name(
    lambda_function::LambdaFunction
  )::String
  describe_log_groups_script = get_describe_log_groups_script()
  log_groups_str = readchomp(`bash -c $describe_log_groups_script`)
  log_groups = JSON3.read(log_groups_str, Dict{String, Vector{LogGroup}})["logGroups"]
  @show lambda_function.FunctionArn
  this_log_groups = filter(log_groups) do group
    endswith(group.arn, "log-group:/aws/lambda/$(lambda_function.FunctionName):*")
  end
  if length(this_log_groups) == 0
    error("Could not find cloudwatch log group corresponding to Lambda function " *
       "$lambda_function.FunctionName"
    )
  end
  if length(this_log_groups) > 1
    error("Found multiple cloudwatch log groups corresponding to Lambda function " *
       "$lambda_function.FunctionName"
    )
  end
  this_log_groups[1].logGroupName
end

function get_target_event(
    event_f::Function,
    event_name::AbstractString,
    events::Vector{LogEvent},
    log_stream_name::AbstractString,
    log_group_name::AbstractString,
  )::Union{Nothing, LogEvent}
  target_events = filter(event_f, events)
  length(target_events) == 0 && error(
    "Found multiple $event_name events in log stream $log_stream_name of log $log_group_name"
  )
  length(target_events) > 1 && error(
    "Found no $event_name event in log stream $log_stream_name of log $log_group_name"
  )
  target_events[1]
end

function get_cloudwatch_log_events(
    log_group_name::String,
    request_id::String,
  )::Tuple{LogEvent, LogEvent, LogEvent, Vector{LogEvent}}
  get_log_streams = get_log_streams_script(log_group_name)
  log_streams_str = readchomp(`bash -c $get_log_streams`)
  log_streams = JSON3.read(
    log_streams_str,
    Dict{String, Vector{LogStream}}
  )["logStreams"]
  if length(log_streams) == 0
    error("Could find no Cloudwatch log streams for $log_group_name")
  end
  this_log_stream = log_streams[begin]
  log_stream_name = this_log_stream.logStreamName
  get_cloudwatch_log_stream_events(log_group_name, log_stream_name)
end

function get_cloudwatch_log_stream_events(
    log_group_name::AbstractString,
    log_stream_name::AbstractString;
    attempts::Int64 = 50,
  )::Tuple{LogEvent, LogEvent, LogEvent, Vector{LogEvent}}
  attempts == 0 && error(
    "Could not find any REPORT event in $log_stream_name of $log_group_name"
  )

  log_events_script = get_log_events_script(log_group_name, log_stream_name)
  log_events_str = readchomp(`bash -c $log_events_script`)
  all_events = JSON3.read(
    log_events_str, Dict{String, Union{String, Vector{LogEvent}}}
  )["events"]

  report_idx_events = filter(collect(enumerate(all_events))) do (i, event)
    startswith(event.message, "REPORT RequestId:")
  end

  this_invocation_events = if length(report_idx_events) == 1
    all_events
  elseif length(report_idx_events) > 1
    penultimate_report_idx = report_idx_events[end - 1] |> first
    all_events[penultimate_report_idx + 1:end]
  else
    []
  end

  start_event_idx = findfirst(is_start_event, this_invocation_events)
  start_event = if isnothing(start_event_idx)
    nothing
  else
    this_invocation_events[start_event_idx]
  end

  end_events = filter(is_end_event, this_invocation_events)
  end_event = length(end_events) == 0 ? nothing : end_events[begin]
  report_events = filter(is_report_event, this_invocation_events)
  report_event = length(report_events) == 0 ? nothing : report_events[begin]

  log_events = filter(this_invocation_events) do event
    !is_start_event(event) &&
    !is_end_event(event) &&
    !is_report_event(event)
  end

  if (
      isnothing(end_event) ||
      isnothing(report_event) ||
      length(log_events) == 0
    )
    sleep(0.1)
    get_cloudwatch_log_stream_events(log_group_name, log_stream_name; attempts = attempts - 1)
  else
    (start_event, end_event, report_event, log_events)
  end
end

