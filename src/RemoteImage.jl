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

"""
    function get_all_remote_images(jot_generated_only::Bool = true)::Vector{RemoteImage}

Returns all remote images stored on AWS ECR. By default, filters for jot-generated images only.
"""
function get_all_remote_images(jot_generated_only::Bool = true)::Vector{RemoteImage}
  repos = get_all_ecr_repos()
  remote_images = [img for repo in repos for img in get_remote_images(repo)]
  jot_generated_only ? filter(is_jot_generated, remote_images) : remote_images
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

Queries AWS and returns a `RemoteImage` instance corresponding to the given `local_image`.

If multiple valid images exist, this will return the first only. If none exists, returns `nothing`.
"""
function get_remote_image(local_image::LocalImage)::Union{Nothing, RemoteImage}
  all_remote_images = get_all_remote_images()
  @debug local_image.Digest
  @debug all_remote_images
  index = findfirst(remote_image -> matches(local_image, remote_image), all_remote_images)
  @debug index
  isnothing(index) ? nothing : all_remote_images[index]
end

"""
    get_remote_image(identity::AbstractString)::Union{Nothing, RemoteImage}

Queries AWS and returns a `RemoteImage` instance corresponding to the given `identity` string.

The identity string will attempt to match on the name of the remote image, or the image's Digest.

If multiple valid images exist, this will return the first only. If none exists, returns `nothing`.
"""
function get_remote_image(identity::AbstractString)::Union{Nothing, RemoteImage}
  all_remote_images = get_all_remote_images()
  index = findfirst(all_remote_images) do ri
    name_matches = get_lambda_name(ri) == identity
    hash_matches = begin
      search_hash = split(identity, ":") |> last
      ri_hash = split(ri.imageDigest, ":") |> last
      comparison_length = minimum([length(search_hash), length(ri_hash)])
      ri_hash[begin:comparison_length] == search_hash[begin:comparison_length]
    end
    name_matches || hash_matches
  end
  isnothing(index) ? nothing : all_remote_images[index]
end

