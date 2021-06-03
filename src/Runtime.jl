using HTTP

export start_runtime

Base.@kwdef struct Invocation
  body::Any
  aws_request_id::String
  deadline_ms::Int
  invoked_function_arn::String
  trace_id::String
end

function get_endpoint(host::String)::String
  "http://$host/2018-06-01/runtime/invocation/"
end

function lambda_respond(response::String, endpoint::String, aws_request_id::String)
  HTTP.request(
    "POST", 
    "$(endpoint)$(aws_request_id)/response", 
    [], 
    response,
  )
end

function lambda_error(error::String, endpoint::String, aws_request_id::String)
  HTTP.request(
    "POST", 
    "$(endpoint)$(aws_request_id)/error", 
    [("Lambda-Runtime-Function-Error-Type", "Unhandled")], 
    JSON3.write(error),
  )
end

function start_runtime(host::String, func_name::String)
  start_runtime(host, eval(Meta.parse(func_name)))
end

function start_runtime(host::String, react_function::Function)
  endpoint = get_endpoint(host)
  println("Starting runtime at $endpoint")

  while true
    http = HTTP.request("GET", "$(endpoint)next"; verbose=3)
    @show http.body
    @info typeof(http.body)
    body_raw = String(http.body)
    @show body_raw
    @info typeof(body_raw)
    request_id = string(HTTP.header(http, "Lambda-Runtime-Aws-Request-Id"))

    body = try
      JSON3.read(body_raw)
    catch e
      body_sample = length(body_raw) > 50 ? "$(body_raw[start:50])..." : body_raw
      @show body_sample
      lambda_error("Unable to parse input JSON $body_sample", endpoint, request_id)
      continue
    end

    reaction = try
      react_function(body)
    catch e
      err(msg) = lambda_error(msg, endpoint, request_id)
      if isa(e, MethodError) && e.f == String(Symbol(react_function))
        err("react function is not a valid method for parsed JSON type")
      else
        err(e.msg)
      end
      continue
    end

    reaction_json = try
      JSON3.write(reaction)
    catch e
      err("Unable to parse function return value $(reaction) to JSON")
      continue
    end

    lambda_respond(reaction_json, endpoint, request_id)
  end
end

