
"""
    mutable struct LocalImage
        CreatedAt::Union{Missing, String} = missing
        Digest::String
        ID::String
        Repository::String
        Size::Union{Missing, String} = missing
        Tag::String
        exists::Bool = true
    end

Represents a docker image on the local machine, and stores associated metadata. Should not be 
instantiated directly. If `exists` is `true`, then the image is assumed to exit and so should be 
visible from utilities such as `docker image ls`.
"""
@with_kw mutable struct LocalImage <: LambdaComponent
  CreatedAt::Union{Missing, String} = missing
  Digest::String
  ID::String
  Repository::String
  Size::Union{Missing, String} = missing
  Tag::String
  exists::Bool = true
end
StructTypes.StructType(::Type{LocalImage}) = StructTypes.Mutable()  
Base.:(==)(a::LocalImage, b::LocalImage) = a.ID[1:docker_hash_limit] == b.ID[1:docker_hash_limit]

function get_image_full_name(image::LocalImage)::String
  image.Repository
end

"""
    get_local_image(
      identity::String,
    )::Union{Nothing, LocalImage}

Returns a `LocalImage` object, representing a locally-stored docker image.

The passed `identity` string may be the repository name, or the docker image ID. If the image ID,
it must be at least four characters in length.
"""
function get_local_image(identity::AbstractString)::Union{Nothing, LocalImage}
  all = get_all_local_images()
  index = findfirst(all) do li
    (li.Repository == identity || begin
       check_len = minimum([length(li.ID), length(identity)])
       li.ID[check_len] == identity[check_len] && check_len >= 4
    end
    )
  end
  isnothing(index) ? nothing : all[index]
end

"""
    get_all_local_images(
      args::Vector{String} = Vector{String}(),
    )::Vector{LocalImage}

Returns `LocalImage` objects for all locally-stored docker images. `args` are passed to the
call to `docker image ls`, that is used to populate this vector.
"""
function get_all_local_images(args::Vector{String} = Vector{String}())::Vector{LocalImage}
  docker_output = readchomp(`docker image ls $args --digests --format '{{json .}}'`)
  parse_docker_ls_output(LocalImage, docker_output)
end

"""
    delete!(
      image::LocalImage; 
      force::Bool=false,
    )

Deletes a locally-stored docker image. The LocalImage instance continues to exist, but has its
`exists` attribute set to `false`.
"""
function delete!(image::LocalImage; force::Bool=false)
  image.exists || error("Image does not exist")
  args = force ? ["--force"] : []
  run(`docker image rm $(image.ID) $args`)
  image.exists = false 
end

function is_lambda(image::LocalImage)::Bool
  occursin(".amazonaws.com/", image.Repository)
end

function get_aws_id(image::LocalImage)::String
  split(image.Repository, '.')[1]
end

function get_aws_region(image::LocalImage)::String
  split(image.Repository, '.')[4]
end

function get_aws_config(image::LocalImage)::AWSConfig
  AWSConfig(get_aws_id(image), get_aws_region(image))
end

function get_image_suffix(image::LocalImage)::String
  split(image.Repository, '/')[2]
end

