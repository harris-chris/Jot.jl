observation_label = "JOT_OBSERVATION"

struct FunctionInvocationLog
    RequestId: String
    observations: Dict{Float64, String}
end
