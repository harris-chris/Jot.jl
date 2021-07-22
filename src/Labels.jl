@with_kw mutable struct Labels
  RESPONDER_PACKAGE_NAME::String = ""
  RESPONDER_FUNCTION_NAME::String = ""
  RESPONDER_COMMIT::Union{Nothing, String} = nothing
  RESPONDER_TREE_HASH::String = ""
  RESPONDER_PKG_SOURCE::Union{Nothing, String} = nothing
  IS_JOT_GENERATED::String = "false" # set to "true" in get_labels(res)
end
StructTypes.StructType(::Type{Labels}) = StructTypes.Mutable()  

function get_responder_full_function_name(labels::Labels)::String
  labels.RESPONDER_PACKAGE_NAME * "." * labels.RESPONDER_FUNCTION_NAME
end
