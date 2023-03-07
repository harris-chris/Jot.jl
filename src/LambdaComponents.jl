
"""
    struct LambdaComponents
        function_name::String
        aws_config::AWSConfig
        local_image::Union{Nothing, LocalImage}
        remote_image::Union{Nothing, RemoteImage}
        lambda_function::Union{Nothing, LambdaFunction}
    end
"""
@with_kw mutable struct LambdaComponents
  function_name::String
  aws_config::AWSConfig
  local_image::Union{Nothing, LocalImage}
  remote_image::Union{Nothing, RemoteImage}
  lambda_function::Union{Nothing, LambdaFunction}
end
Base.show(l::LambdaComponents) = "$(l.local_image)\t$(l.remote_image)\t$(l.lambda_function)"

function get_from_any_component(
    get_func::Function,
    l::LambdaComponents,
  )
  for (f_name, f_type) in zip(fieldnames(LambdaComponents), fieldtypes(LambdaComponents))
    if f_type <: LambdaComponent
      try
        out = get_func(getfield(l, f_name))
        return out
      catch e
        continue
      end
    end
  end
end

"""
    create_lambda_components(
        res::AbstractResponder;
        image_suffix::Union{Nothing, String} = nothing,
        aws_config::Union{Nothing, AWSConfig} = nothing,
        image_tag::String = "latest",
        no_cache::Bool = false,
        julia_base_version::String = "1.8.4",
        julia_cpu_target::String = "x86-64",
        function_test_data::Union{Nothing, FunctionTestData} = nothing,
        user_defined_labels::AbstractDict{String, String} = OrderedDict{String, String}(),
      )::LambdaComponents

Creates a `LocalImage` from the given responder, creates a `LambdaComponents` object to store the
local image, and then returns the `LambdaComponents` object.

Acts as an alternative to `create_local_image`, but returns a `LambdaComponents` rather than just
the local image. This can be more convenient for keeping the components of a lambda function
organized - for example:
`create_lambda_components(responder) |> with_remote_image! |> with_lambda_function!` will run through
the entire process of creating a local image, pushing that image to ECR, and then creating a Lambda
function.
"""
function create_lambda_components(
    res::AbstractResponder;
    image_suffix::Union{Nothing, String} = nothing,
    aws_config::Union{Nothing, AWSConfig} = nothing,
    image_tag::String = "latest",
    no_cache::Bool = false,
    julia_base_version::String = "1.8.4",
    julia_cpu_target::String = "x86-64",
    function_test_data::Union{Nothing, FunctionTestData} = nothing,
    user_defined_labels::AbstractDict{String, String} = OrderedDict{String, String}(),
    dockerfile_update::Function = x -> x,
  )::LambdaComponents
  local_image = create_local_image(res;
                                   image_suffix = image_suffix,
                                   aws_config = aws_config,
                                   image_tag = image_tag,
                                   no_cache = no_cache,
                                   julia_base_version = julia_base_version,
                                   julia_cpu_target = julia_cpu_target,
                                   function_test_data = function_test_data,
                                   user_defined_labels = user_defined_labels,
                                   dockerfile_update = dockerfile_update)
  LambdaComponents(get_response_function_name(local_image),
                   get_aws_config(),
                   local_image,
                   nothing,
                   nothing,
  )
end

"""
    with_remote_image!(l::LambdaComponents)::LambdaComponents

Adds a 'RemoteImage` object to the passed `LambdaComponents` instance. Will error if the instance
has neither an existing remote image or local image.
"""
function with_remote_image!(l::LambdaComponents)::LambdaComponents
  if isnothing(l.local_image) && isnothing(l.remote_image)
    error("Unable to add remote image to LambdaComponents as it does not have a local image")
  end
  if isnothing(l.remote_image)
    l.remote_image = push_to_ecr!(l.local_image)
    l
  else
    l
  end
end

"""
    with_lambda_function!(l::LambdaComponents)::LambdaComponents

Adds a 'LambdaFunction` instance to the passed `LambdaComponents` instance. Will error if the instance
has neither an existing remote image, local image or lambda function.
"""
function with_lambda_function!(l::LambdaComponents)::LambdaComponents
  with_remote = if isnothing(l.remote_image) && isnothing(l.lambda_function)
    try
      with_remote_image!(l)
    catch e
      error("Unable to create lambda function from LambdaComponents; it has neither a local image nor a remote image")
    end
  else
    l
  end
  if isnothing(with_remote.lambda_function)
    l.lambda_function = create_lambda_function(with_remote.remote_image)
    l
  else
    l
  end
end

"""
    delete!(l::LambdaComponents)

Deletes the local docker image, remote image, and lambda function associated with the
`LambdaComponents` instance.
"""
function delete!(l::LambdaComponents)
  !isnothing(l.lambda_function) && delete!(l.lambda_function)
  !isnothing(l.remote_image) && delete!(l.remote_image)
  !isnothing(l.local_image) && delete!(l.local_image)
end

"""
    run_test(
        l::LambdaComponents;
        function_argument::Any = "",
        expected_response::Any = nothing,
      )::Tuple{Bool, Union{Missing, LambdaFunctionInvocationLog, Float64}}

Tests the passed `LambdaComponents` instance.

The test runs on the most downstream object. So if the instance has a `LambdaFunction`, this will
be tested. Otherwise, the attached `LocalImage` will be tested. If the `LambdaComponents` object
has neither a local image or a lambda function, then it has nothing that can be tested and the
function will throw an error.

Returns a tuple of {Test pass/fail, Test time taken in seconds}.
"""
function run_test(
    l::LambdaComponents,
    function_argument::Any = "",
    expected_response::Any = nothing,
  )::Tuple{Bool, Union{Missing, LambdaFunctionInvocationLog, Float64}}
  if !isnothing(l.lambda_function)
    run_lambda_function_test(l.lambda_function, function_argument, expected_response)
  elseif !isnothing(l.local_image)
    run_local_image_test(l.local_image, function_argument, expected_response)
  else
    error("Unable to test LambdaComponents object; it has neither a local image or a lambda function")
  end
end

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
        get_tree_hash(dirname(responder_path)) == lc_tree_hash
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

local_image_name_f(l::LambdaComponents)::String = isnothing(l.local_image) ? not_present : get_lambda_name(l.local_image)
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

"""
    show_lambdas()::Nothing

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

