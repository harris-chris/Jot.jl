"""
    @with_kw mutable struct RemoteImage
        imageDigest::Union{Missing, String} = missing
        imageTag::Union{Missing, String} = missing
        ecr_repo::Union{Missing, ECRRepo} = missing
        exists::Bool = true
    end

Represents a docker image stored in an AWS ECR Repository. The `exists` attribute indicates whether
the RemoteImage still exists.
"""
@with_kw mutable struct RemoteImage <: LambdaComponent
  imageDigest::Union{Missing, String} = missing
  imageTag::Union{Missing, String} = missing
  ecr_repo::Union{Missing, ECRRepo} = missing
  exists::Bool = true
end
StructTypes.StructType(::Type{RemoteImage}) = StructTypes.Mutable()  
Base.:(==)(a::RemoteImage, b::RemoteImage) = a.imageDigest == b.imageDigest


function get_all_remote_images()::Vector{RemoteImage}
  repos = get_all_ecr_repos()
  @debug repos
  [img for repo in repos for img in get_remote_images(repo)]
end

function get_remote_images(repo::ECRRepo)::Vector{RemoteImage}
  @debug repo
  get_images_script = get_images_in_ecr_repo_script(repo)
  @debug get_images_script
  images_json = readchomp(`bash -c $get_images_script`)
  images = JSON3.read(images_json, Dict{String, Vector{RemoteImage}})["imageIds"]
  map(images) do img
    @set img.ecr_repo = repo
  end
end

function delete!(r::RemoteImage)
  r.exists || error("Remote image does not exist")
  delete_script = get_delete_remote_image_script(r)
  output = readchomp(`bash -c $delete_script`)
  r.exists = false
  if length(get_remote_images(r.ecr_repo)) == 0
    delete!(r.ecr_repo)
  end
  nothing
end

"""
    get_remote_image(local_image::LocalImage)::Union{Nothing, RemoteImage}

Queries AWS and returns a `RemoteImage` instance corresponding to the given `local_image`. If none 
exists, returns `nothing`.
"""
function get_remote_image(local_image::LocalImage)::Union{Nothing, RemoteImage}
  all_remote_images = get_all_remote_images()
  @debug local_image.Digest
  @debug all_remote_images
  index = findfirst(remote_image -> matches(local_image, remote_image), all_remote_images)
  @debug index
  isnothing(index) ? nothing : all_remote_images[index]
end

function get_remote_image(image_hash::String)::Union{Nothing, RemoteImage}
  all_remote_images = get_all_remote_images()
  search_hash = split(image_hash, ":") |> last
  index = findfirst(all_remote_images) do ri
    ri_hash = split(ri.imageDigest, ":") |> last
    comparison_length = minimum([length(search_hash), length(ri_hash)])
    ri_hash[begin:comparison_length] == search_hash[begin:comparison_length]
  end
  isnothing(index) ? nothing : all_remote_images[index]
end

function get_image_suffix(remote_image::RemoteImage)::String
  get_image_suffix(remote_image.ecr_repo)
end
