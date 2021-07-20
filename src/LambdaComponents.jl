
"""
    struct LambdaComponents
        aws_config::AWSConfig
        local_image::Union{Nothing, LocalImage}
        remote_image::Union{Nothing, RemoteImage}
        lambda_function::Union{Nothing, LambdaFunction}
    end
"""
@with_kw struct LambdaComponents
  function_name::String
  aws_config::AWSConfig
  local_image::Union{Nothing, LocalImage}
  remote_image::Union{Nothing, RemoteImage}
  lambda_function::Union{Nothing, LambdaFunction}
end
Base.show(l::LambdaComponents) = "$(l.local_image)\t$(l.remote_image)\t$(l.lambda_function)"

function matches(res::AbstractResponder, local_image::LocalImage)::Bool
  tree_hash = get_tree_hash(local_image)
  isnothing(tree_hash) ? false : (get_tree_hash(res) == tree_hash)
end
matches(local_image::LocalImage, res::AbstractResponder) = matches(res, local_image)

function matches(local_image::LocalImage, ecr_repo::ECRRepo)::Bool
  local_image.Repository == ecr_repo.repositoryUri
end
matches(ecr_repo::ECRRepo, local_image::LocalImage) = matches(local_image, ecr_repo)

function matches(local_image::LocalImage, remote_image::RemoteImage)::Bool
  local_image.Digest == remote_image.imageDigest
end
matches(remote_image::RemoteImage, local_image::LocalImage) = matches(local_image, remote_image)

function matches(res::AbstractResponder, remote_image::RemoteImage)::Bool
  tree_hash = get_tree_hash(remote_image)
  isnothing(tree_hash) ? false : get_tree_hash(res) == tree_hash
end
matches(remote_image::RemoteImage, res::AbstractResponder) = matches(res, remote_image)

function matches(remote_image::RemoteImage, lambda_function::LambdaFunction)::Bool
  hash_only = split(remote_image.imageDigest, ':')[2]
  hash_only == lambda_function.CodeSha256
end
matches(lambda_function::LambdaFunction, remote_image::RemoteImage) = matches(remote_image, lambda_function)

function combine_if_matches(l1::LambdaComponents, l2::LambdaComponents)::Union{Nothing, LambdaComponents}
  get_non_nothing_type(x::Type{IT}) where {IT} = typeof(x) == Union ? x.b : x

  lambda_types = map(get_non_nothing_type, fieldtypes(LambdaComponents))
  lambda_names = fieldnames(LambdaComponents)
  l1_fields = [getfield(l1, name) for name in lambda_names]
  l2_fields = [getfield(l2, name) for name in lambda_names]

  function match_across_fields(
      l1_flds::Vector, 
      l2_flds::Vector,
    )::Bool
    for (fieldtype_1, val_1) in zip(lambda_types, l1_flds)
      for (fieldtype_2, val_2) in zip(lambda_types, l2_flds)
        if !isnothing(val_1) && !isnothing(val_2) && hasmethod(matches, Tuple{fieldtype_1, fieldtype_2})
          if matches(val_1, val_2)
            return true
          end
        end
      end
    end
    return false
  end

  function cmb(c1::Union{Nothing, T}, c2::Union{Nothing, T})::Union{Nothing, T} where {T}
    if isnothing(c1)
      c2
    elseif isnothing(c2)
      c1
    else
      c1 != c2 && error("Found non-matching element in matched lambda")
      c1
    end
  end

  function cmb(c1::T, c2::T)::T where {T}
    c1 != c2 && error("Found non-matching element in matched lambda")
    c1
  end

  if match_across_fields(l1_fields, l2_fields)
    cmb_fields = Dict(sym => cmb(f_1, f_2) for (sym, f_1, f_2) in zip(lambda_names, l1_fields, l2_fields))
    LambdaComponents(; cmb_fields...)
  else
    nothing
  end
end

struct TableComponent
  name::String
  value_function::Function
  highlighter_f::Union{Function, Nothing}
end

const not_present = "-"

function_name_f(l::LambdaComponents)::String = l.function_name
const function_name_component = TableComponent("Function Name", function_name_f, nothing)

function account_id_f(l::LambdaComponents)::String
  l.aws_config.account_id
end
const account_id_component = TableComponent("Account ID", account_id_f, nothing)

function responder_source_f(l::LambdaComponents)::String
  src = get_labels(l).RESPONDER_PKG_SOURCE
  isnothing(src) ? not_present : src
end
function responder_source_h_f(
    headers::OrderedDict{String, TableComponent}, lambdas::Vector{LambdaComponents},
  )::Vector{Highlighter}
  h1 = Highlighter(bold = true, foreground = :blue) do table_data, i, j
    comps = values(headers) |> collect
    if comps[j] == responder_source_component
      responder_path = table_data[i, j]
      lc_tree_hash = get_tree_hash(lambdas[i])
      if ispath(responder_path)
        get_tree_hash(responder_path) == lc_tree_hash
      else
        false
      end
    else
      false
    end
  end

  h2 = Highlighter(foreground = :dark_gray) do table_data, i, j
    comps = values(headers) |> collect
    if comps[j] == responder_source_component
      responder_path = table_data[i, j]
      ispath(responder_path) ? false : true
    else
      false
    end
  end
  [h1, h2]
end
const responder_source_component = TableComponent("Responder Source", responder_source_f, responder_source_h_f)

function tree_hash_f(l::LambdaComponents)::String
  isnothing(l.local_image) && return not_present 
  hsh = get_tree_hash(l.local_image)
  isnothing(hsh) ? not_present : hsh[1:docker_hash_limit]
end
const tree_hash_component = TableComponent("Tree Hash", tree_hash_f, nothing)

local_image_name_f(l::LambdaComponents)::String = isnothing(l.local_image) ? not_present : get_image_suffix(l.local_image)
const local_image_name_component = TableComponent("Image Name", local_image_name_f, nothing)

local_image_id_f(l::LambdaComponents)::String = isnothing(l.local_image) ? not_present : l.local_image.ID 
const local_image_id_component = TableComponent("Image ID", local_image_id_f, nothing)

local_image_tag_f(l::LambdaComponents)::String = isnothing(l.local_image) ? not_present : l.local_image.Tag
const local_image_tag_component = TableComponent("Image Tag", local_image_tag_f, nothing)

function remote_image_tag_f(l::LambdaComponents)::String 
  isnothing(l.remote_image) && return not_present
  itag = l.remote_image.imageTag
  ismissing(itag) ? not_present : itag
end
const remote_image_tag_component = TableComponent("Image Tag", remote_image_tag_f, nothing)

function remote_image_digest_f(l::LambdaComponents)::String 
  isnothing(l.remote_image) && return "-"
  digest = l.remote_image.imageDigest
  if ismissing(digest)
    "-"
  else
    hash_only = split(digest, ':') |> last
    hash_only[begin:docker_hash_limit]
  end
end
const remote_image_digest_component = TableComponent("Image Digest", remote_image_digest_f, nothing)

function lambda_function_name_f(l::LambdaComponents)::String 
  isnothing(l.lambda_function) && return not_present
  fn = l.lambda_function.FunctionName 
  ismissing(fn) ? not_present : fn
end
const lambda_function_name_component = TableComponent("Function Name", lambda_function_name_f, nothing)

function lambda_function_last_modified_f(l::LambdaComponents)::String 
  isnothing(l.lambda_function) && return not_present
  lm = l.lambda_function.LastModified
  ismissing(lm) ? not_present : lm
end
const lambda_function_last_modified_component = TableComponent(
  "Last Modified", lambda_function_last_modified_f, nothing
)

function get_table_data(
    headers::OrderedDict{String, TableComponent},
    lambdas::Vector{LambdaComponents}, 
  )::Matrix{String}

  # TODO refactor common interface for all getters - check component then check sub
  # TODO highlight responder path if not current - probably put it in grey
  all_funcs = values(headers) |> collect
  data_rows = [map(tc -> tc.value_function(l), all_funcs) for l in lambdas]
  data_rows = map(row-> reshape(row, (1, :)), data_rows)
  data = vcat(data_rows...)
end

function show_lambdas()
  @info "Collecting lambda components; this may take a few seconds..."
  lambdas = get_all_lambdas()

  table_headers = OrderedDict(
    "Function Name" => function_name_component,
    "Responder" => responder_source_component,
    "Local Image" => local_image_id_component,
    "Remote Image" => remote_image_digest_component,
    "Lambda Function" => lambda_function_name_component,
  )

  table_data = get_table_data(table_headers, lambdas)
  headers_matrix = (keys(table_headers) |> collect, [tc.name for tc in values(table_headers)])

  table_comps = filter(tc -> !isnothing(tc.highlighter_f), values(table_headers) |> collect)
  highlighter_funcs = map(tc -> tc.highlighter_f, table_comps)
  highlighters = [h for hf in highlighter_funcs for h in hf(table_headers, lambdas)]
  highlighters = tuple(highlighters...)
  
  pretty_table(
    table_data; 
    header=headers_matrix, 
    show_row_number=true, 
    crop=:none,
    maximum_columns_width=30,
    highlighters=highlighters,
  )
end

function get_all_lambdas()::Vector{LambdaComponents}
  all_local = get_all_local_images()
  all_remote = get_all_remote_images()
  all_functions = get_all_lambda_functions()
  aws_config = get_aws_config()
  local_lambdas = [ 
    LambdaComponents(get_labels(l) |> get_responder_full_function_name, aws_config, l, nothing, nothing) 
    for l in all_local if (is_lambda(l) && is_jot_generated(l))
  ]
  remote_lambdas = [
    LambdaComponents(get_labels(r) |> get_responder_full_function_name, aws_config, nothing, r, nothing) 
    for r in all_remote if is_jot_generated(r)
  ]
  func_lambdas = [
    LambdaComponents(get_labels(f) |> get_responder_full_function_name, aws_config, nothing, nothing, f) 
    for f in all_functions if is_jot_generated(f)
  ]
  all_lambdas = [ local_lambdas ; remote_lambdas ; func_lambdas ]

  function match_off_lambdas(
      to_match::Vector{LambdaComponents}, 
      matched::Vector{LambdaComponents}
  )::Vector{LambdaComponents}
    if length(to_match) == 0
      matched
    else
      match_head = to_match[1]; match_tail = to_match[2:end]
      add_to_matched = match_head
      for (i, m) in enumerate(matched)
        cmb = combine_if_matches(match_head, m)
        if !isnothing(cmb) 
          add_to_matched = cmb
          deleteat!(matched, i)
          break
        end
      end
      match_off_lambdas(match_tail, [matched; [add_to_matched]])
    end
  end
  match_off_lambdas(all_lambdas, Vector{LambdaComponents}())
end

function group_by_function_name(lambdas::Vector{LambdaComponents})::Dict{String, Vector{LambdaComponents}}
  has_local_image = filter(l -> !isnothing(l.local_image), lambdas)
  func_names = map(l -> get_response_function_name(l.local_image), has_local_image) 
  lambdas_by_function = Dict()
  for (func_name, lambda) in zip(func_names, has_local_image)
    if !isnothing(lambda.local_image)
      if !isnothing(func_name)
        lambdas_for_name = get(lambdas_by_function, mod_func_name, Vector{LambdaComponents}())
        lambdas_by_function[mod_func_name] = [lambdas_for_name ; [lambda]]
      end
    end
  end
  lambdas_by_function
end

"""
    show_all_lambdas(
      local_image_attr::String = "tag", 
      remote_image_attr::String = "tag",  
      lambda_function_attr::String = "version",
    )::Nothing

Displays a table of all objects generated using Jot.jl.

Each row of the table shows at least one of a Responder, a local docker image, a remote (hosted
on AWS ECR) docker image, and an AWS-hosted Lambda function. The local docker image, remote docker
image and lambda function on a given row of the table are guaranteed to share the same underlying 
function code.

The Responder column is colour-coded:
- Grey indicates that this path no longer exists.
- White indicates that this path still exists, but the code has changed since the objects shown
in the row were created.
- Blue indicates that the underlying code for this row (eg the code present in the local image,
remote image etc) is the same as is currently present at this path.
"""
function show_all_lambdas(; 
    local_image_attr::String = "tag", 
    remote_image_attr::String = "tag",  
    lambda_function_attr::String = "version",
  )::Nothing
  out = ""
  out *= "\tLocal Image\tRemote Image\tLambda Function"
  for l in get_all_lambdas()
    out *= "\n$(get_response_function_name(l.local_image))"
    # Header
    li_attr = if local_image_attr == "tag"
      l.local_image.Tag
    elseif local_image_attr == "created at"
      l.local_image.CreatedAt
    elseif local_image_attr == "id"
      l.local_image.ID[1:docker_hash_limit]
    elseif local_image_attr == "digest"
      l.local_image.Digest[1:docker_hash_limit]
    end

    ri_attr = if isnothing(l.remote_image)
      ""
    else
      if remote_image_attr == "tag"
        l.remote_image.imageTag
      elseif remote_image_attr == "digest"
        l.remote_image.imageDigest[1:docker_hash_limit]
      end
    end

    lf_attr = if isnothing(l.lambda_function)
      ""
    else
      if lambda_function_attr == "version"
        l.lambda_function.Version
      elseif lambda_function_attr == "digest"
        l.lambda_function.CodeSha256
      end
    end
    out *= "\t$li_attr\t$ri_attr\t$lf_attr"
  end
  println(out)
end
