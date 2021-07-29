using SpecialFunctions

function map_log_gamma(v::Vector{N}) where {N <: Number}
  return map(loggamma, v)
end
