
# TODO some way to make this have abstract attributes eg package_name?
"""
    abstract type AbstractResponder{IT} end

The supertype of all responder types. The type parameter represents the parameter type of the 
`response_function` responder attribute.
"""
abstract type AbstractResponder{IT} end

"""
    struct LocalPackageResponder{IT} <: AbstractResponder{IT}
        pkg::Pkg.Types.PackageSpec
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
  response_function::Symbol
  response_function_param_type::Type{IT}
  build_dir::String
  package_name::String

  function LocalPackageResponder(
      pkg::Pkg.Types.PackageSpec,
      response_function::Symbol,
      ::Type{IT},
      build_dir::String,
      package_name::String,
    )::LocalPackageResponder{IT} where {IT}
    new{IT}(pkg, response_function, IT, build_dir, package_name)
  end

  function LocalPackageResponder(
      pkg::Pkg.Types.PackageSpec,
      response_function::Symbol,
      ::Type{IT},
    )::LocalPackageResponder{IT} where {IT}
    build_dir = create_build_directory()
    path = pkg.repo.source
    package_name = get_responder_package_name(path)
    move_local_to_build_directory(build_dir, path, package_name)
    println("Pinned $package_name.$response_function with tree hash $(get_tree_hash(build_dir)) to $build_dir")
    new{IT}(pkg, response_function, IT, build_dir, package_name)
  end

  function LocalPackageResponder(
      path::String,
      response_function::Symbol,
      ::Type{IT},
    )::LocalPackageResponder{IT} where {IT}
    isdir(path) || error("Unable to find local directory $(path)")
    path = path[end] == '/' ? path[1:end-1] : path |> abspath
    pkg_spec = PackageSpec(path=path)
    LocalPackageResponder(pkg_spec, response_function, IT)
  end
end

struct RemoteResponder{IT} <: AbstractResponder{IT}
  url::String
  response_function::Symbol
  response_function_param_type::Type{IT}
end

function LocalScriptResponder(
    local_path::String,
    response_function::Symbol,
    ::Type{IT};
    dependencies = Vector{String}(),
  )::LocalPackageResponder{IT} where {IT}
  build_dir = create_build_directory()
  pkg_name = "jot_" * randstring("abcdefghijklmnopqrstuvwxyz1234567890", 12)
  @show pwd()
  @show readdir()
  cd(build_dir) do
    Pkg.generate(pkg_name)
    Pkg.activate("./$pkg_name")
    length(dependencies) > 0 && Pkg.add(dependencies)
    open("./$pkg_name/Project.toml", "r") do f
      @debug read(f)
    end
  end
  @show readdir(joinpath(build_dir, pkg_name))
  @show dependencies
  script = open(local_path, "r") do f
    read(f) |> String
  end
  pkg_code = """
  module $pkg_name\n
  $script\n
  end\n
  """
  @show readdir(joinpath(build_dir, pkg_name, "src"))
  open(joinpath(build_dir, pkg_name, "src", pkg_name * ".jl"), "w") do f
    write(f, pkg_code)
  end
  LocalPackageResponder(
                        PackageSpec(path=joinpath(build_dir, pkg_name)),
                        response_function,
                        IT,
                        build_dir,
                        pkg_name,
                       )
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

`path_url` may point to either a script or a package. If a script, `dependencies` 
may be passed to specify any dependencies used in the script. If a package, the dependencies will
be found automatically from its `Project.toml`.

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
    RemoteResponder(path_url, response_function, IT)
  elseif isrelativeurl(path_url)
    if isdir(path_url) 
      if "Project.toml" in readdir(path_url)
        length(dependencies) > 0 && error("""
          Dependencies have been passed, but path_url leads to a package; please specify dependencies in the Package's Project.toml
          """
        )
        LocalPackageResponder(path_url, response_function, IT)
      else
        error("""
        Path points to a directory, but no Project.toml exists; please provide a path to either a package directory, or a script file"
        """)
      end
    elseif(isfile(path_url))
      LocalScriptResponder(joinpath(pwd(), path_url), response_function, IT; dependencies)
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
  LocalPackageResponder{IT}(pkg_path, response_function, IT)
end

function get_responder_package_name(path::String)::String
  open(joinpath(path, "Project.toml"), "r") do file
    proj = file |> TOML.parse
    proj["name"]
  end
end

function get_commit(res::LocalPackageResponder)::String
  get_commit(res.build_dir)
end

function get_responder_function_name(res::LocalPackageResponder)::String
  res.response_function |> String
end
