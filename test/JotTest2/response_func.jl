using SpecialFunctions

function response_func(v::Vector{N}) where {N <: Number}
  return map(loggamma, v)
end
