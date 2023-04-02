
"""
    struct Responder{IT}
        local_path::String
        response_function::Symbol
        response_function_param_type::Type{IT}
        registry_urls::Vector{String}
        source_path::AbstractString
    end

A responder, stored at the location pointed to by `local_path`, and a valid Julia
package. This is not instantiated directly, but created via the `get_responder`
function.
"""
mutable struct Responder{IT}
  local_path::String
  response_function::Symbol
  response_function_param_type::Type{IT}
  registry_urls::Vector{String}
  source_path::AbstractString
end

function get_responder_from_local_package(
    path::String,
    response_function::Symbol,
    ::Type{IT},
    registry_urls::Vector{String},
  )::Responder{IT} where {IT}
  isdir(path) || error("Unable to find local directory $(path)")
  "Project.toml" in readdir(path) || error("Unable to find Project.toml in $path")
  path = path[end] == '/' ? path[1:end-1] : path |> abspath
  Responder(path, response_function, IT, registry_urls, path)
end

function get_responder_from_package_url(
    url::String,
    response_function::Symbol,
    ::Type{IT},
    registry_urls::Vector{String},
  )::Responder{IT} where {IT}
  build_dir = mktempdir()
  local_path = cd(build_dir) do
    Pkg.activate(".")
    dev_dir = get(ENV, "JULIA_PKG_DEVDIR", nothing)
    ENV["JULIA_PKG_DEVDIR"] = build_dir
    initial_build_dir_contents = readdir(build_dir)
    Pkg.develop(PackageSpec(url=url))
    pkg_dir = [
      x for x in readdir(build_dir, join=true)
      if !(x in initial_build_dir_contents) && isdir(x)
    ] |> last
    if !isnothing(dev_dir) ENV["JULIA_PKG_DEVDIR"] = dev_dir end
    pkg_dir
  end

  Responder(
    local_path, response_function, IT, registry_urls, url
  )
end

function get_responder_from_local_script(
    local_path::String,
    response_function::Symbol,
    ::Type{IT},
    dependencies::Vector{String},
    registry_urls::Vector{String},
  )::Responder{IT} where {IT}
  !isfile(local_path) && error("$local_path does not point to a file")
  build_dir = create_build_directory!()
  script_filename = basename(local_path)
  pkg_name = get_package_name_from_script_name(script_filename)
  cd(build_dir) do
    # Pkg.develop(path=abspath(pwd()))
    Pkg.generate(pkg_name)
    Pkg.activate("./$pkg_name")
    for registry_url in registry_urls
      Pkg.Registry.add(RegistrySpec(url = registry_url))
    end
    length(dependencies) > 0 && Pkg.add(dependencies)
  end
  script = open(local_path, "r") do f
    read(f) |> String
  end
  pkg_code = """
  module $pkg_name\n
  export $(String(response_function))
  $script\n
  end\n
  """
  open(joinpath(build_dir, pkg_name, "src", pkg_name * ".jl"), "w") do f
    write(f, pkg_code)
  end
  Pkg.activate()
  Responder(
    joinpath(build_dir, pkg_name), response_function, IT, registry_urls, local_path
  )
end

function get_package_name_from_script_name(filename::String)::String
  pkg_name = filename[end-2:end] == ".jl" ? filename[begin:end-3] : filename
  replace_chars = ["-", ".", ",", ":", ";"]
  for r in replace_chars
    pkg_name = replace(pkg_name, r => "_")
  end
  pkg_name * "_package"
end

Base.:(==)(a::Responder, b::Responder) = get_tree_hash(a) == get_tree_hash(b)

function Base.show(res::Responder)::String
  "$(get_response_function_name(res)) from $(res.local_path) with tree hash " *
  "$(get_tree_hash(res))"
end

"""
    function get_responder(
        path_url::String,
        response_function::Symbol,
        response_function_param_type::Type{IT};
        dependencies::Vector{<:AbstractString} = Vector{String}(),
        registry_urls::Vector{<:AbstractString} = Vector{String}(),
      )::Responder{IT} where {IT}

Returns an Responder, a type that holds the function that will be used to respond to AWS
Lambda calls.

`path_url` may be either a local filesystem path, or a url.

If a filesystem path, it may point to either a script or a package. If a script, `dependencies`
may be passed to specify any dependencies used in the script. If a package, the dependencies will
be found automatically from its `Project.toml`.

If a url, it should be a remote package, for example the URL for a github repo. The url given will
be passed to `Pkg` as a url, so any url valid in a `PackageSpec` will also be valid here, such as
https://github.com/harris-chris/JotTest3

`response_function` is a function within this module that you would like to use to respond to AWS
Lambda calls. `response_function_param_type` specifies the type that the response function is
expecting as its only argument.

`registry_urls` may be used to make additional julia registries available, the packages from which can then be used in the `dependencies` parameter.
"""
function get_responder(
    path_url::String,
    response_function::Symbol,
    response_function_param_type::Type{IT};
    dependencies::Vector{<:AbstractString} = Vector{String}(),
    registry_urls::Vector{<:AbstractString} = Vector{String}(),
  )::Responder{IT} where {IT}
  if isurl(path_url)
    get_responder_from_package_url(
      path_url, response_function, IT, registry_urls,
    )
  elseif isrelativeurl(path_url)
    normalised_path = normpath(path_url)
    if isdir(normalised_path)
      if "Project.toml" in readdir(normalised_path)
        length(dependencies) > 0 && error("""
          Dependencies have been passed, but normalised_path leads to a package; please specify dependencies in the Package's Project.toml
          """
        )
        get_responder_from_local_package(
          normalised_path, response_function, IT, registry_urls
        )
      else
        error("""
        Path points to a directory, but no Project.toml exists; please provide a path to either a package directory, or a script file
        """)
      end
    elseif(isfile(normalised_path))
      abs_path = joinpath(pwd(), normalised_path)
      get_responder_from_local_script(
        abs_path, response_function, IT, dependencies, registry_urls
      )
    else
      error("Unable to find path $normalised_path")
    end
  else
    error("path/url $path_url not recognized")
  end
end

"""
    function get_responder(
        mod::Module,
        response_function::Symbol,
        response_function_param_type::Type{IT};
        registry_urls::Vector{<:AbstractString} = Vector{String}(),
      )::Responder{IT} where {IT}

Returns an Responder, a type that holds the function that will be used to respond to AWS
Lambda calls.

`mod` is a module currently in scope, and response_function is a function within this module that
you would like to use to respond to AWS Lambda calls.

`response_function` is a function within this module that you would like to use to respond to AWS
Lambda calls. `response_function_param_type` specifies the type that the response function is
expecting as its only argument.

`registry_urls` may be used to make additional julia registries available, the packages from which can then be used in the `dependencies` parameter.
"""
function get_responder(
    mod::Module,
    response_function::Symbol,
    response_function_param_type::Type{IT};
    registry_urls::Vector{<:AbstractString} = Vector{String}(),
  )::Responder{IT} where {IT}
  pkg_path = get_package_path(mod)
  get_responder_from_local_package(pkg_path, response_function, IT, registry_urls)
end

function get_responder_path(res::Responder)::String
  res.local_path
end

function get_package_name(res::Responder)::String
  open(joinpath(get_responder_path(res), "Project.toml"), "r") do file
    proj = file |> TOML.parse
    proj["name"]
  end
end

function get_commit(res::Responder)::String
  get_commit(get_responder_path(res))
end

function get_responder_function_name(res::Responder)::String
  res.response_function |> String
end
