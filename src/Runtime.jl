using HTTP

export start_runtime

abstract type AWSError end

Base.@kwdef struct ProcessError <: AWSError
  errorType::String
  errorMessage::String
end

function process_reaction(reaction::InvocationResponse, aws_request_id::String, endpoint::String)
  response = HTTP.request(
    "POST", 
    "$(endpoint)$(aws_request_id)/response", 
    [], 
    reaction.response
  )
end

function process_reaction(reaction::InvocationError, aws_request_id::String, endpoint::String)
  response = HTTP.request(
    "POST", 
    "$(endpoint)$(aws_request_id)/error", 
    [("Lambda-Runtime-Function-Error-Type", "Unhandled")], 
    json(reaction),
  )
end

function process_reaction(reaction::AWSError, aws_request_id::String, endpoint::String)
  response = HTTP.request(
    "POST", 
    "$(endpoint)$(aws_request_id)/error", 
    [("Lambda-Runtime-Function-Error-Type", "Unhandled")], 
    json(reaction),
  )
end

function start_runtime(host::String, react_function::Function)
  endpoint = "http://$host/2018-06-01/runtime/invocation/"
  println("Starting runtime at $endpoint")

  while true
    http = HTTP.request("GET", "$(endpoint)next"; verbose=3)
    body = try
      JSON.parse(String(http.body))
    catch e
      err = ProcessError("JSON Parsing Error", e.msg)
      process_reaction(
                       err,
                       string(HTTP.header(http, "Lambda-Runtime-Aws-Request-Id")),
                       endpoint)
      continue
    end
      
    invocation = Invocation(
      body=body,
      aws_request_id=HTTP.header(http, "Lambda-Runtime-Aws-Request-Id"),
      deadline_ms=parse(Int, HTTP.header(http, "Lambda-Runtime-Deadline-Ms")),
      invoked_function_arn=HTTP.header(http, "Lambda-Runtime-Invoked-Function-Arn"),
      trace_id=HTTP.header(http, "Lambda-Runtime-Trace-Id"),
    )

    reaction = react_function(invocation)
    process_reaction(reaction, invocation.aws_request_id, endpoint)
  end
end

if abspath(PROGRAM_FILE) == @__FILE__
  start_runtime(ARGS[1])
end
