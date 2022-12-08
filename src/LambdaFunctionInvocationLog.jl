@enum JotObservationLabel begin
  JOT_OBSERVATION
  JOT_AWS_LAMBDA_REQUEST_ID
end

const BOOTSTRAP_STARTED_JOT_OBSERVATION = "$JOT_OBSERVATION Bootstrap started ..."
const STARTING_JULIA_JOT_OBSERVATION = "$JOT_OBSERVATION Starting Julia ..."
const JULIA_STARTED_JOT_OBSERVATION = "$JOT_OBSERVATION ... Julia started"

"""
    struct LogEvent
      timestamp::Int64
      message::String
      ingestionTime::Int64
    end

A single item of log output from AWS Cloudwatch, returned within a LambdaFunctionInvocationLog.
"""
struct LogEvent
  timestamp::Int64
  message::String
  ingestionTime::Int64
end

function is_start_event(event::LogEvent)::Bool
  startswith(event.message, "START RequestId:")
end

function is_end_event(event::LogEvent)::Bool
  startswith(event.message, "END RequestId:")
end

function is_precompile_event(event::LogEvent)::Bool
  startswith(event.message, "precompile(")
end

function is_report_event(event::LogEvent)::Bool
  startswith(event.message, "REPORT RequestId:")
end

function is_debug_event(event::LogEvent)::Bool
  startswith(event.message, "DEBUG:")
end

function is_observation_event(event::LogEvent)::Bool
  startswith(event.message, "$JOT_OBSERVATION")
end

function is_defined_event(event::LogEvent)::Bool
  is_start_event(event) ||
  is_end_event(event) ||
  is_report_event(event) ||
  is_debug_event(event) ||
  is_observation_event(event)
end

"""
    struct LambdaFunctionInvocationLog
      RequestId::String
      cloudwatch_log_group_name::String
      cloudwatch_log_start_event::Union{Nothing, LogEvent}
      cloudwatch_log_end_event::LogEvent
      cloudwatch_log_report_event::LogEvent
      cloudwatch_log_events::Vector{LogEvent}
    end

The log output from a Lambda function invocation, obtained via `invoke_function_with_log`.
"""
struct LambdaFunctionInvocationLog
  RequestId::String
  cloudwatch_log_group_name::String
  cloudwatch_log_start_event::Union{Nothing, LogEvent}
  cloudwatch_log_end_event::LogEvent
  cloudwatch_log_report_event::LogEvent
  cloudwatch_log_events::Vector{LogEvent}
end

struct LogGroup
  logGroupName::String
  creationTime::Int64
  metricFilterCount::Int64
  arn::String
  storedBytes::Int64
end

struct LogStream
  logStreamName::String
  creationTime::Int64
  firstEventTimestamp::Int64
  lastEventTimestamp::Int64
  lastIngestionTime::Int64
  uploadSequenceToken::String
  arn::String
  storedBytes::Int64
end

"""
    struct InvocationTimeBreakdown
      total::Float64
      ex_responder_function_time::Union{Nothing, Float64}
      precompile_time::Union{Nothing, Float64}
      responder_function_time::Float64
    end

A simple time breakdown of a single AWS Lambda invocation. `total` should be close to or the same as the sum of alll other attributes in the struct.

`ex_responder_function_time` means all of the time spent outside of the responder function.

`precompile_time` is the time that Julia has spent pre-compiling functions, as they are used for the first time.

`responder_function_time` means all the time spent within the responder function, excluding any precompile time within the function.

If an attribute is `nothing`, this means that this process did not run at all. For example, if an AWS Lambda function is already available, it may not need to start Julia and therefore the `ex_responder_function_time` will be `nothing`.
"""
struct InvocationTimeBreakdown
  total::Float64
  ex_responder_function_time::Union{Nothing, Float64}
  precompile_time::Union{Nothing, Float64}
  responder_function_time::Float64
end

function unix_epoch_time_to_datetime(epoch_time::Int64)::DateTime
  epoch_time_seconds = floor(Int64, epoch_time/1000)
  milliseconds = epoch_time - (epoch_time_seconds * 1000)
  datetime_seconds = Dates.unix2datetime(epoch_time_seconds)
  datetime_seconds + Dates.Millisecond(milliseconds)
end

"""
    show_observations(
        log::LambdaFunctionInvocationLog,
      )::Nothing

Presents a visual breakdown of the time spent for a given Lambda invocation. Only Jot observation points will be shown here. See the 'Debugging Performance' page for more details of this.
"""
function show_observations(log::LambdaFunctionInvocationLog)::Nothing
  show_log_events(log.cloudwatch_log_events, is_observation_event, "Jot observation")
end

"""
    show_log_events(
        log::LambdaFunctionInvocationLog,
      )::Nothing

Presents a visual breakdown of the time spent for a given Lambda function invocation. All logged events will be shown here.
"""
function show_log_events(log::LambdaFunctionInvocationLog)::Nothing
  show_log_events(log.cloudwatch_log_events, x -> true, "Any log event")
end

"""
    get_invocation_time_breakdown(
        log::LambdaFunctionInvocationLog,
      )::InvocationTimeBreakdown

Returns an `InvocationTimeBreakdown` object, which stores how/where the total run-time was spent for a given invocation, in milliseconds.
"""
function get_invocation_time_breakdown(
    log::LambdaFunctionInvocationLog
  )::InvocationTimeBreakdown
  log_events = log.cloudwatch_log_events
  starting_julia_idx = findfirst(log_events) do event
    event.message == "$STARTING_JULIA_JOT_OBSERVATION"
  end
  pre_responder_function_time = if isnothing(starting_julia_idx)
    nothing
  else
    log_events[starting_julia_idx].timestamp - log_events[begin].timestamp
  end

  julia_started_idx = findfirst(log_events) do event
    event.message == "$JULIA_STARTED_JOT_OBSERVATION"
  end

  starting_julia_idx = isnothing(starting_julia_idx) ? 1 : starting_julia_idx
  julia_started_idx = isnothing(julia_started_idx) ? length(log_events) : julia_started_idx

  last_event_timestamp = log_events[starting_julia_idx].timestamp
  (precompile_time, responder_function_time) = foldl(
    log_events[starting_julia_idx+1:julia_started_idx]; init = (0.0, 0.0)
  ) do acc, event
    this_time = event.timestamp - last_event_timestamp
    last_event_timestamp = event.timestamp
    if is_precompile_event(event)
      (first(acc) + this_time, last(acc))
    else
      (first(acc), last(acc) + this_time)
    end
  end

  post_responder_function_time = (
    log_events[end].timestamp - log_events[julia_started_idx].timestamp
  )
  ex_responder_function_time = if (
    !isnothing(pre_responder_function_time) && !isnothing(post_responder_function_time)
  )
    pre_responder_function_time + post_responder_function_time
  elseif !isnothing(pre_responder_function_time)
    pre_responder_function_time
  elseif !isnothing(post_responder_function_time)
    post_responder_function_time
  else
    nothing
  end

  InvocationTimeBreakdown(
    get_invocation_run_time(log),
    ex_responder_function_time,
    precompile_time,
    responder_function_time,
  )
end

function show_log_events(
    log_events::Vector{LogEvent},
    should_event_be_shown::Function,
    event_type::AbstractString,
  )::Nothing
  start_time_unix = log_events[1].timestamp
  last_event_unix = start_time_unix
  valid_events = filter(should_event_be_shown, log_events)
  if length(valid_events) == 0
    println("No log events of type $event_type found within all log events")
  else
    first_valid_event_is_first_event = valid_events[1].timestamp == log_events[1].timestamp
    have_prior_log_event = if !first_valid_event_is_first_event
      println("Log starts")
      true
    else
      false
    end

    foreach(valid_events) do event
      total_elapsed_time = event.timestamp - start_time_unix
      from_last_elapsed_time = event.timestamp - last_event_unix
      if have_prior_log_event
        println("    |")
        println("    + $from_last_elapsed_time ms")
        println("    |")
      end
      println("Total time elapsed: $total_elapsed_time ms")
      message_body = chopprefix(event.message, "$JOT_OBSERVATION")
      println(strip("Observation: $message_body"))
      last_event_unix = event.timestamp
      have_prior_log_event = true
    end
    if valid_events[end].timestamp != log_events[end].timestamp
      from_last_elapsed_time = log_events[end].timestamp - valid_events[end].timestamp
      println("    |")
      println("    + $from_last_elapsed_time ms")
      println("    |")
      println("Log ends")
    end
  end
end

"""
    get_invocation_run_time(
        log::LambdaFunctionInvocationLog,
      )::Float64

Returns the total run time for a given lambda function invocation, expressed in milliseconds.
"""
function get_invocation_run_time(log::LambdaFunctionInvocationLog)::Float64
  get_invocation_run_time(log.cloudwatch_log_report_event)
end

function get_invocation_run_time(report_event::LogEvent)::Float64
  lines = split(report_event.message, '\t')
  duration_lines = filter(lines) do line
    startswith(line, "Duration:")
  end
  length(duration_lines) == 0 && error("Found no duration lines in event $report_event")
  length(duration_lines) > 1 && error("Found multiple duration lines in event $report_event")
  duration_line = duration_lines[1]
  duration_str = chopsuffix(chopprefix(duration_line, "Duration: "), " ms")
  parse(Float64, duration_str)
end

