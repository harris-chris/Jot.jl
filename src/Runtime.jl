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

function start_runtime(host::String, func_name::String, param_type::String; single_shot=false)
  param_type = eval(Meta.parse(param_type))
  start_runtime(host, eval(Meta.parse(func_name)), param_type)
end

function start_runtime(
    host::String, react_function::Function, ::Type{T}; single_shot=false
  ) where {T}
  tmp_contents = readdir("/tmp")
  println("$JOT_OBSERVATION Contents of tmp before starting loop $tmp_contents")
  depot_contents = readdir("/var/runtime/julia_depot")
  println("$JOT_OBSERVATION Contents of var/runtime/julia_depot before starting loop $depot_contents")
  endpoint = get_endpoint(host)
  println("$JOT_OBSERVATION Starting Julia runtime at $endpoint")

  while true
    @info "$(endpoint)next"
    http = HTTP.request("GET", "$(endpoint)next"; verbose=3)
    body_raw = String(http.body)
    println("HTTP headers")
    println(http.headers)
    request_id = string(HTTP.header(http, "Lambda-Runtime-Aws-Request-Id"))
    println("$JOT_OBSERVATION $JOT_AWS_LAMBDA_REQUEST_ID : $request_id")

    println("$JOT_OBSERVATION Received invocation message, parsing to JSON ...")
    body = try
      JSON3.read(body_raw, T)
    catch e
      body_sample = length(body_raw) > 50 ? "$(body_raw[start:50])..." : body_raw
      lambda_error("Unable to parse input JSON $body_sample", endpoint, request_id)
      continue
    end

    println("$JOT_OBSERVATION ... invocation message parsed, calling responder function ...")
    reaction = try
      react_function(body)
    catch e
      err(msg) = lambda_error(msg, endpoint, request_id)
      if isa(e, MethodError) && e.f == String(Symbol(react_function))
        err("react function is not a valid method for parsed JSON type")
      else
        err("$e")
      end
      continue
    end
    println("$JOT_OBSERVATION ... received response from responder function, writing to JSON ...")

    reaction_json = try
      JSON3.write(reaction)
    catch e
      err("Unable to parse function return value $(reaction) to JSON")
      continue
    end

    println("$JOT_OBSERVATION ... JSON created, posting response to AWS Lambda ...")
    lambda_respond(reaction_json, endpoint, request_id)
    println("$JOT_OBSERVATION ... Response posted, invocation finished")
    tmp_contents = readdir("/tmp")
    println("$JOT_OBSERVATION Contents of tmp at end of loop $tmp_contents")
    depot_contents = readdir("/var/runtime/julia_depot")
    println("$JOT_OBSERVATION Contents of var/runtime/julia_depot at end of loop $depot_contents")
    single_shot && break
  end
  tmp_contents = readdir("/tmp")
  println("$JOT_OBSERVATION Contents of tmp at very end of loop $tmp_contents")
end

