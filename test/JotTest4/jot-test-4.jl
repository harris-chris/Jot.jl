using SpecialFunctions
using PRAS # From added registry

function map_log_gamma(v::Vector{N}) where {N <: Number}
  return map(loggamma, v)
end
