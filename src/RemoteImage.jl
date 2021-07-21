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
@with_kw mutable struct RemoteImage
  imageDigest::Union{Missing, String} = missing
  imageTag::Union{Missing, String} = missing
  ecr_repo::Union{Missing, ECRRepo} = missing
  exists::Bool = true
end
StructTypes.StructType(::Type{RemoteImage}) = StructTypes.Mutable()  
Base.:(==)(a::RemoteImage, b::RemoteImage) = a.imageDigest == b.imageDigest

function get_all_remote_images()::Vector{RemoteImage}
  repos = get_all_ecr_repos()
  remote_images = Vector{RemoteImage}()
  for repo in repos
    images_json = readchomp(`aws ecr list-images --repository-name=$(repo.repositoryName)`)
    images = JSON3.read(images_json, Dict{String, Vector{RemoteImage}})["imageIds"]
    for image in images
      push!(remote_images, RemoteImage(imageDigest=image.imageDigest,
                                       imageTag=image.imageTag,
                                       ecr_repo=repo))
    end
  end
  remote_images
end

"""
    get_remote_image(local_image::LocalImage)::Union{Nothing, RemoteImage}

Queries AWS and returns a `RemoteImage` instance corresponding to the given `local_image`. If none 
exists, returns `nothing`.
"""
function get_remote_image(local_image::LocalImage)::Union{Nothing, RemoteImage}
  all_remote_images = get_all_remote_images()
  index = findfirst(remote_image -> matches(local_image, remote_image), all_remote_images)
  isnothing(index) ? nothing : all_remote_images[index]
end
