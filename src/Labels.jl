@with_kw mutable struct Labels
  RESPONDER_PACKAGE_NAME::String = ""
  RESPONDER_FUNCTION_NAME::String = ""
  RESPONDER_COMMIT::Union{Nothing, String} = nothing
  RESPONDER_TREE_HASH::String = ""
  RESPONDER_PKG_SOURCE::Union{Nothing, String} = nothing
  IS_JOT_GENERATED::String = "false" # set to "true" in get_labels(res)
  user_defined_labels::Dict{String, String} = Dict{String, String}()
end
StructTypes.StructType(::Type{Labels}) = StructTypes.Mutable()  

function Labels(d::AbstractDict{String, String})::Labels
  field_names = map(String, fieldnames(Labels))
  kwargs = Dict{Symbol, Any}()
  user_defined_labels = Dict{String, String}()
  for (k, v) in d
    if k in field_names
      kwargs[Symbol(k)] = v
    else
      user_defined_labels[k] = v
    end
  end
  kwargs[:user_defined_labels] = user_defined_labels
  Labels(; kwargs...)
end

function copy(l::Labels)::Labels
  flds = Dict(Symbol(fn) => getfield(l, fn) for fn in fieldnames(Labels))
  Labels(;flds...)
end

function get_responder_full_function_name(labels::Labels)::String
  labels.RESPONDER_PACKAGE_NAME * "." * labels.RESPONDER_FUNCTION_NAME
end

function to_aws_shorthand(l::Labels)::String
  normal_tags = join(
    ["$k=$(getfield(l, k))" for k in fieldnames(Labels) if k != :user_defined_labels], 
    ",")
  addnl_tags = join(["$k=$v" for (k,v) in l.user_defined_labels], ",")
  normal_tags * "," * addnl_tags
end

function to_json(l::Labels)::String
  normal_tags = [
    OrderedDict("Key" => String(k), "Value" => (isnothing(getfield(l, k)) ? "" : getfield(l, k)))
    for k in fieldnames(Labels) if k != :user_defined_labels
  ] 
  addnl_tags = [OrderedDict("Key" => k, "Value" => v) for (k, v) in l.user_defined_labels]
  JSON3.write([ normal_tags ; addnl_tags ])
end

function to_docker_buildfile_format(l::Labels)::String
  normal_labels = join(
    ["$(String(k))=$(getfield(l, k))" for k in fieldnames(Labels) if k != :user_defined_labels], 
    " ",
  )
  user_defined_labels = join(["$k=$v" for (k, v) in l.user_defined_labels], " ") 
  normal_labels * " " * user_defined_labels
end

function add_user_defined_labels(l::Labels, new_tags::Dict{String, String})::Labels
  c_l = copy(l)
  c_l.user_defined_labels = merge(c_l.user_defined_labels, new_tags)
  c_l
end

