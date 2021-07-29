
"""
    mutable struct Container
        ID::String
        Image::String
        Command::Union{Missing, String} = missing
        CreatedAt::Union{Missing, String} = missing
        Names::Union{Missing, String} = missing
        Ports::Union{Missing, String} = missing
        exists::Bool = true
    end

Represents a docker container on the local environment. Should not be instantiated directly. If 
`exists` is `true`, then the container is assumed to exit and so should be visible from utilities 
such as `docker container ls --all`.
"""
@with_kw mutable struct Container
  ID::String
  Image::String
  Command::Union{Missing, String} = missing
  CreatedAt::Union{Missing, String} = missing
  Names::Union{Missing, String} = missing
  Ports::Union{Missing, String} = missing
  exists::Bool = true
end
Base.:(==)(a::Container, b::Container) = a.ID[1:docker_hash_limit] == b.ID[1:docker_hash_limit]

"""
    is_container_running(con::Container)::Bool

Returns `true` if the given docker container is currently running (not stopped).
"""
function is_container_running(con::Container)::Bool
  running_containers = get_all_containers()
  @debug running_containers
  @debug con
  con in running_containers
end

"""
    stop_container(con::Container)

Stops the given docker container, if currently running.
"""
function stop_container(con::Container)
  if is_container_running(con)
    run(`docker stop $(con.ID)`)
  end
end

"""
    delete!(con::Container)

Deletes the passed container from the local docker system. The `Container` instance continues to 
exist, but has its `exists` attribute set to `false`.

"""
function delete!(con::Container)
  con.exists || error("Container does not exist")
  run(`docker container rm $(con.ID)`)
  con.exists = false
end

"""
    get_all_containers(args::Vector{String} = Vector{String}())::Vector{Container}

Returns a list of containers currently available on the local machine.

`args` are additional arguments passed to the `docker ps` call that this function wraps.
"""
function get_all_containers(args::Vector{String} = Vector{String}())::Vector{Container}
  docker_output = readchomp(`docker ps $args --format '{{json .}}'`)
  parse_docker_ls_output(Container, docker_output)
end

function get_all_containers(image::LocalImage; args::Vector{String}=Vector{String}())::Vector{Container}
  @debug image.ID
  get_all_containers([
                  ["--filter", "ancestor=$(image.ID[1:docker_hash_limit])"]
                  args
                 ])
end

