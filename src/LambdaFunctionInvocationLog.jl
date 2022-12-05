@enum JotObservationLabel begin
  JOT_OBSERVATION
  JOT_AWS_LAMBDA_REQUEST_ID
end

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

Presents a visual breakdown of the time spent for a given Lambda invocation. Only Jot observation points will be shown here.
"""
function show_observations(log::LambdaFunctionInvocationLog)::Nothing
  show_log_events(log.cloudwatch_log_events, is_observation_event, "Jot observation")
end

"""
    show_observations(
        log::LambdaFunctionInvocationLog,
      )::Nothing

Presents a visual breakdown of the time spent for a given Lambda function invocation. All logged events will be shown here.
"""
function show_log_events(log::LambdaFunctionInvocationLog)::Nothing
  show_log_events(log.cloudwatch_log_events, x -> true, "Any log event")
end

"""
    get_invocation_precompile_time(
        log::LambdaFunctionInvocationLog,
      )::Float64

Returns the total time that Julia spent precompiling functions during a given invocation, in milliseconds.
"""
function get_invocation_precompile_time(log::LambdaFunctionInvocationLog)::Float64
  last_time = log.cloudwatch_log_events[begin].timestamp
  foldl(log.cloudwatch_log_events; init=0.0) do total_time_taken, event
    this_time_taken = is_precompile_event(event) ? event.timestamp - last_time : 0.0
    last_time = event.timestamp
    total_time_taken + this_time_taken
  end
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

