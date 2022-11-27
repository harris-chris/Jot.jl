observation_label = "JOT_OBSERVATION"
request_id_label = "JOT_AWS_LAMBDA_REQUEST_ID"

struct LogEvent
  timestamp::Int64
  message::String
  ingestionTime::Int64
end

struct LambdaFunctionInvocationLog
  RequestId::String
  cloudwatch_log_group_name::String
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

