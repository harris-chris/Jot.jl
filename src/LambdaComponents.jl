
"""
    struct LambdaComponents
        local_image::Union{Nothing, LocalImage}
        remote_image::Union{Nothing, RemoteImage}
        lambda_function::Union{Nothing, LambdaFunction}
    end
"""
struct LambdaComponents
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
  lambda_types = fieldtypes(LambdaComponents)
  lambda_names = fieldnames(LambdaComponents)
  l1_fields = [getfield(l1, name) for name in lambda_names]
  l2_fields = [getfield(l2, name) for name in lambda_names]

  function matches(
      l1_fields::Vector, 
      l2_fields::Vector,
    )::Bool where {A, B}
    for (t_1, nm_1, val_1) in zip(lambda_types, lambda_names, l1_fields)
      for (t_2, nm_2, val_2) in zip(lambda_types, lambda_names, l2_fields)
        if hasmethod(matches, Tuple{t_1, t_2})
          if matches(val_1, val_2)
            return true
          end
        end
      end
    end
    return false
  end

  function cmb(::Type{T}, c1::Union{Nothing, T}, c2::Union{Nothing, T})::Union{Nothing, T} where {T}
    if isnothing(c1)
      c2
    elseif isnothing(c2)
      c1
    else
      c1 != c2 && error("Found non-matching element in matched lamda")
      c1
    end
  end

  if matches(l1_fields, l2_fields)
    cmb_fields = Dict(sym => cmb(f_1, f_2) for ((sym, _, f_1), (_, _, f_2)) in zip(l1_fields, l2_fields))
    LambdaComponents(cmb_fields...)
  else
    nothing
  end
end
  
function to_table(lambdas::Vector{LambdaComponents})::Tuple{OrderedDict{String, Vector{String}}, Matrix{String}}
  # TODO refactor common interface for all getters - check component then check sub
  headers = OrderedDict("AWS Config" => ["Account ID"],
                 "Response Function" => ["Function Name", "Tree Hash"],
                 "Local Image" => ["Image Name", "ID", "Tag"],
                 "Remote Image" => ["Tag"],
                 "Lambda Function" => ["Name", "Last Modified"],
                )
  function d11(l::LambdaComponents)::String
    isnothing(l.local_image) && return ""
    aid = get_aws_config(l.local_image).account_id
    ismissing(aid) ? "" : aid
  end
  function d21(l::LambdaComponents)::String 
    isnothing(l.local_image) && return ""
    rfn = get_response_function_name(l.local_image)
    isnothing(rfn) ? "" : rfn
  end
  function d22(l::LambdaComponents)::String
    isnothing(l.local_image) && return "" 
    hsh = get_tree_hash(l.local_image)
    isnothing(hsh) ? "" : hsh[1:docker_hash_limit]
  end
  d31(l::LambdaComponents)::String = isnothing(l.local_image) ? "" : get_image_suffix(l.local_image)
  d32(l::LambdaComponents)::String = isnothing(l.local_image) ? "" : l.local_image.ID 
  d33(l::LambdaComponents)::String = isnothing(l.local_image) ? "" : l.local_image.Tag
  function d41(l::LambdaComponents)::String 
    isnothing(l.remote_image) && return ""
    itag = l.remote_image.imageTag
    ismissing(itag) ? "" : itag
  end
  function d51(l::LambdaComponents)::String 
    isnothing(l.lambda_function) && return ""
    fn = l.lambda_function.FunctionName 
    ismissing(fn) ? "" : fn
  end
  function d52(l::LambdaComponents)::String 
    isnothing(l.lambda_function) && return ""
    lm = l.lambda_function.LastModified
    ismissing(lm) ? "" : lm
  end

  data = vcat([[d11(l) d21(l) d22(l) d31(l) d32(l) d33(l) d41(l) d51(l) d52(l)] for l in lambdas]...)
  (headers, data)
end

function show_lambdas()
  lambdas = get_all_lambdas()
  (headers, data) = to_table(lambdas)
  headers_matrix = ([x for (top, bottom) in headers for x in fill(top, length(bottom))],
                    [x for bottom in values(headers) for x in bottom])
  pretty_table(data; header=headers_matrix)
end

function get_all_lambdas()::Vector{LambdaComponents}
  all_local = get_all_local_images()
  all_remote = get_all_remote_images()
  all_functions = get_all_lambda_functions()
  local_lambdas = [ LambdaComponents(l, nothing, nothing) for l in all_local if is_lambda(l)]
  remote_lambdas = [ LambdaComponents(nothing, r, nothing) for r in all_remote ]
  func_lambdas = [ LambdaComponents(nothing, nothing, f) for f in all_functions ]
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
      for m in matched
        cmb = combine_if_matches(match_head, m)
        if !isnothing(cmb) 
          add_to_matched = cmb
          break
        end
      end
      match_off_lambdas(match_tail, push!(matched, add_to_matched))
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

function show_all_lambdas(; 
    local_image_attr::String = "tag", 
    remote_image_attr::String = "tag",  
    lambda_function_attr::String = "version",
  )
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
