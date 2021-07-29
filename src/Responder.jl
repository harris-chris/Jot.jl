
"""
    abstract type AbstractResponder{IT} end

The supertype of all responder types. The type parameter represents the parameter type of the 
`response_function` responder attribute.
"""
abstract type AbstractResponder{IT} end

"""
    struct LocalPackageResponder{IT} <: AbstractResponder{IT}
        pkg::Pkg.Types.PackageSpec
        original_path::String
        response_function::Symbol
        response_function_param_type::Type{IT}
        build_dir::String
        package_name::String
    end

A responder that is located locally (in the temporary `build_dir`) and is a Julia package. This is
usually created by the `Responder` function.
"""
mutable struct LocalPackageResponder{IT} <: AbstractResponder{IT}
  # TODO: remove pkg attribute?
  pkg::Pkg.Types.PackageSpec
  original_path::String
  response_function::Symbol
  response_function_param_type::Type{IT}
  build_dir::String
  package_name::String
end

function get_responder_from_local_package(
    path::String,
    response_function::Symbol,
    ::Type{IT},
  )::LocalPackageResponder{IT} where {IT}
  isdir(path) || error("Unable to find local directory $(path)")
  "Project.toml" in readdir(path) || error("Unable to find Project.toml in $path")
  path = path[end] == '/' ? path[1:end-1] : path |> abspath
  pkg_spec = PackageSpec(path=path)
  get_responder_from_package_spec(pkg_spec, response_function, IT)
end

function get_responder_from_package_spec(
      pkg::Pkg.Types.PackageSpec,
      response_function::Symbol,
      ::Type{IT},
    )::LocalPackageResponder{IT} where {IT}
    build_dir = create_build_directory()
    path = pkg.repo.source
    package_name = get_responder_package_name(path)
    move_local_to_build_directory(build_dir, path, package_name)
    println("Pinned $package_name.$response_function with tree hash $(get_tree_hash(build_dir)) to $build_dir")
    LocalPackageResponder(pkg, path, response_function, IT, build_dir, package_name)
  end

function get_responder_from_package_url(
    url::String,
    response_function::Symbol,
    ::Type{IT};
  )::LocalPackageResponder{IT} where {IT}
  build_dir = create_build_directory()
  dev_dir = get(ENV, "JULIA_PKG_DEVDIR", nothing)
  current_build_dir_contents = readdir(build_dir)
  ENV["JULIA_PKG_DEVDIR"] = build_dir
  Pkg.develop(url=url)
  if !isnothing(dev_dir) ENV["JULIA_PKG_DEVDIR"] = dev_dir end
  new_dir = [x for x in readdir(build_dir) if !(x in current_build_dir_contents)] |> last
  pkg_name = get_responder_package_name(joinpath(build_dir, new_dir))
  Pkg.rm(pkg_name)
  LocalPackageResponder(
                        PackageSpec(url=url),
                        url,
                        response_function,
                        IT,
                        build_dir,
                        pkg_name,
                       )
end



function get_responder_from_local_script(
    local_path::String,
    response_function::Symbol,
    ::Type{IT};
    dependencies = Vector{String}(),
  )::LocalPackageResponder{IT} where {IT}
  !isfile(local_path) && error("$local_path does not point to a file")
  build_dir = create_build_directory()
  # pkg_name = "script_" * randstring("abcdefghijklmnopqrstuvwxyz1234567890", 8)
  script_filename = basename(local_path)
  pkg_name = get_package_name_from_script_name(script_filename)
  cd(build_dir) do
    Pkg.generate(pkg_name)
    Pkg.activate("./$pkg_name")
    length(dependencies) > 0 && Pkg.add(dependencies)
  end
  script = open(local_path, "r") do f
    read(f) |> String
  end
  pkg_code = """
  module $pkg_name\n
  $script\n
  end\n
  """
  open(joinpath(build_dir, pkg_name, "src", pkg_name * ".jl"), "w") do f
    write(f, pkg_code)
  end
  LocalPackageResponder(
                        PackageSpec(path=joinpath(build_dir, pkg_name)),
                        local_path,
                        response_function,
                        IT,
                        build_dir,
                        pkg_name,
                       )
end

function get_image_suffix_from_responder(res::AbstractResponder)::String
  lowercase(res.package_name)
end

function get_package_name_from_script_name(filename::String)::String
  pkg_name = filename[end-2:end] == ".jl" ? filename[begin:end-3] : filename
  replace_chars = ["-", ".", ",", ":", ";"]
  for r in replace_chars
    pkg_name = replace(pkg_name, r => "_")
  end
  pkg_name * "_package"
end

Base.:(==)(a::LocalPackageResponder, b::LocalPackageResponder) = get_tree_hash(a) == get_tree_hash(b)

function Base.show(res::LocalPackageResponder)::String
  "$(get_response_function_name(res)) from $(res.package_spec.repo.source) with tree hash $(get_tree_hash(res))"
end

"""
    function get_responder(
        path_url::String, 
        response_function::Symbol,
        response_function_param_type::Type{IT};
        dependencies = Vector{String}(),
      )::AbstractResponder{IT} where {IT}
Returns an AbstractResponder, a type that holds the function that will be used to respond to AWS
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
"""
function get_responder(
    path_url::String, 
    response_function::Symbol,
    response_function_param_type::Type{IT};
    dependencies = Vector{String}(),
  )::AbstractResponder{IT} where {IT}
  if isurl(path_url)
    get_responder_from_package_url(path_url, response_function, IT)
  elseif isrelativeurl(path_url)
    if isdir(path_url) 
      if "Project.toml" in readdir(path_url)
        length(dependencies) > 0 && error("""
          Dependencies have been passed, but path_url leads to a package; please specify dependencies in the Package's Project.toml
          """
        )
        get_responder_from_local_package(path_url, response_function, IT)
      else
        error("""
        Path points to a directory, but no Project.toml exists; please provide a path to either a package directory, or a script file
        """)
      end
    elseif(isfile(path_url))
      get_responder_from_local_script(joinpath(pwd(), path_url), response_function, IT; dependencies)
    else
      error("Unable to find path $path_url")
    end
  else
    error("path/url $path_url not recognized")
  end
end

"""
    function get_responder(
        package_spec::Pkg.Types.PackageSpec, 
        response_function::Symbol,
        response_function_param_type::Type{IT};
        dependencies = Vector{String}(),
      )::AbstractResponder{IT} where {IT}

Returns an AbstractResponder, a type that holds the function that will be used to respond to AWS
Lambda calls.  

`package_spec` is an instance of `PackageSpec`, part of the standard Julia `Pkg` library.

`response_function` is a function within this module that you would like to use to respond to AWS 
Lambda calls. `response_function_param_type` specifies the type that the response function is 
expecting as its only argument.
"""
function get_responder(
    package_spec::Pkg.Types.PackageSpec, 
    response_function::Symbol,
    response_function_param_type::Type{IT};
  )::AbstractResponder{IT} where {IT}
  if !isnothing(package_spec.repo.source)
    get_responder(package_spec.repo.source, response_function, IT)
  else
    error("Not implemented")
  end
end

"""
    function get_responder(
        mod::Module, 
        response_function::Symbol,
        response_function_param_type::Type{IT},
      )::AbstractResponder{IT} where {IT}

Returns an AbstractResponder, a type that holds the function that will be used to respond to AWS
Lambda calls.  

`mod` is a module currently in scope, and response_function is a function within this module that 
you would like to use to respond to AWS Lambda calls.

`response_function` is a function within this module that you would like to use to respond to AWS 
Lambda calls. `response_function_param_type` specifies the type that the response function is 
expecting as its only argument.
"""
function get_responder(
    mod::Module, 
    response_function::Symbol,
    response_function_param_type::Type{IT},
  )::LocalPackageResponder{IT} where {IT}
  pkg_path = get_package_path(mod)
  get_responder_from_local_package(pkg_path, response_function, IT)
end

function get_responder_package_name(path::String)::String
  open(joinpath(path, "Project.toml"), "r") do file
    proj = file |> TOML.parse
    proj["name"]
  end
end

function get_responder_path(res::LocalPackageResponder)::Union{Nothing, String}
  res.original_path
end

function get_commit(res::LocalPackageResponder)::String
  get_commit(res.build_dir)
end

function get_responder_function_name(res::LocalPackageResponder)::String
  res.response_function |> String
end
