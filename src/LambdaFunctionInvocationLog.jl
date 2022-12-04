@enum JotObservationLabel begin
  JOT_OBSERVATION
  JOT_AWS_LAMBDA_REQUEST_ID
end

struct LogEvent
  timestamp::Int64
  message::String
  ingestionTime::Int64
end

"""
    struct LambdaFunctionInvocationLog
      RequestId::String
      cloudwatch_log_group_name::String
      cloudwatch_log_end_event::LogEvent
      cloudwatch_log_report_event::LogEvent
      cloudwatch_log_debug_events::Vector{LogEvent}
    end

The log output from a Lambda function invocation, obtained via `invoke_function_with_log`.
"""
struct LambdaFunctionInvocationLog
  RequestId::String
  cloudwatch_log_group_name::String
  cloudwatch_log_end_event::LogEvent
  cloudwatch_log_report_event::LogEvent
  cloudwatch_log_debug_events::Vector{LogEvent}
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

function show_observations(log::LambdaFunctionInvocationLog)::Nothing
  start_time_unix = log.cloudwatch_log_debug_events[1].timestamp
  last_event_unix = start_time_unix
  observations = filter(log.cloudwatch_log_debug_events) do event
    startswith("$JOT_OBSERVATION", event.message)
  end
  if observations[1] != log.cloudwatch_log_debug_events[1].timestamp
    println("First log event")
  end
  foreach(observation) do event
    total_elapsed_time = event.timestamp - start_time_unix
    from_last_elapsed_time = event.timestamp - last_event_unix
    if elapsed_time != 0
      println("    |")
      println("    + $from_last_elapsed_time ms")
      println("    |")
    end
    println("Time elapsed: $total_elapsed_time ms")
    message_body = chopprefix(event.message, "$JOT_OBSERVATION")
    println("Observation: $message_body")
  end
end

function get_invocation_run_time(log::LambdaFunctionInvocationLog)::Float64
  get_invocation_run_time(log.cloudwatch_log_report_event)
end

function get_invocation_run_time(report_event::LogEvent)::Float64
  lines = split(report_event.message, '\t')
  @show lines
  duration_lines = filter(lines) do line
    startswith(line, "Duration:")
  end
  length(duration_lines) == 0 && error("Found no duration lines in event $report_event")
  length(duration_lines) > 1 && error("Found multiple duration lines in event $report_event")
  duration_line = duration_lines[1]
  duration_str = chopsuffix(chopprefix(duration_line, "Duration: "), " ms")
  parse(Float64, duration_str)
end

