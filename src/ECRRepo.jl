
"""
    @with_kw mutable struct ECRRepo
        repositoryArn::Union{Missing, String} = missing
        registryId::Union{Missing, String} = missing
        repositoryName::Union{Missing, String} = missing
        repositoryUri::Union{Missing, String} = missing
        createdAt::Union{Missing, String} = missing
        imageTagMutability::Union{Missing, String} = missing
        imageScanningConfiguration::Union{Missing, Any} = missing
        encryptionConfiguration::Union{Missing, Any} = missing
        exists::Bool = true
    end

Represents an AWS ECR (Elastic Container Registry) Repo. Should not be instantiated directly.
If `exists` is `true`, then the image is assumed to exit and so should be visible from utilities
such as `docker image ls`.
"""
@with_kw mutable struct ECRRepo
  repositoryArn::Union{Missing, String} = missing
  registryId::Union{Missing, String} = missing
  repositoryName::Union{Missing, String} = missing
  repositoryUri::Union{Missing, String} = missing
  createdAt::Union{Missing, String} = missing
  imageTagMutability::Union{Missing, String} = missing
  imageScanningConfiguration::Union{Missing, Any} = missing
  encryptionConfiguration::Union{Missing, Any} = missing
  exists::Bool = true
end
StructTypes.StructType(::Type{ECRRepo}) = StructTypes.Mutable()
Base.:(==)(a::ECRRepo, b::ECRRepo) = a.repositoryUri == b.repositoryUri

"""
    get_ecr_repo(image::LocalImage)::Union{Nothing, ECRRepo}

Queries AWS and returns an `ECRRepo` instance that is associated with the passed `local_image`.
Returns `nothing` if one cannot be found.
"""
function get_ecr_repo(local_image::LocalImage)::Union{Nothing, ECRRepo}
  all_repos = get_all_ecr_repos()
  image_full_name = get_image_full_name(local_image)
  index = findfirst(repo -> repo.repositoryUri == image_full_name, all_repos)
  isnothing(index) ? nothing : all_repos[index]
end

"""
    get_all_ecr_repos(jot_generated_only::Bool = true)::Vector{ECRRepo}

Returns a vector of `ECRRepo`s, representing all AWS-hosted ECR Repositories.

`jot_generated_only` specifies whether to filter for jot-generated repos only.
"""
function get_all_ecr_repos(jot_generated_only::Bool = true)::Vector{ECRRepo}
  all_repos_json = readchomp(`aws ecr describe-repositories`)
  all = JSON3.read(all_repos_json, Dict{String, Vector{ECRRepo}})
  all_repos = all["repositories"]
  jot_generated_only ? filter(is_jot_generated, all_repos) : all_repos
end

"""
    get_ecr_repo(repo_name::String)::Union{Nothing, ECRRepo}

Queries AWS and returns an `ECRRepo` instance with the passed `repo_name`.
Returns `nothing` if one cannot be found.
"""
function get_ecr_repo(repo_name::String)::Union{Nothing, ECRRepo}
  all_repos = get_all_ecr_repos()
  index = findfirst(repo -> repo.repositoryName == repo_name, all_repos)
  isnothing(index) ? nothing : all_repos[index]
end

function create_ecr_repo(image::LocalImage)::ECRRepo
  image.exists || error("Image does not exist")
  labels = get_labels(image)
  create_script = get_create_ecr_repo_script(
                                             get_lambda_name(image),
                                             get_aws_region(image),
                                             labels,
                                            )
  repo_json = readchomp(`bash -c $create_script`)
  @debug repo_json
  JSON3.read(repo_json, Dict{String, ECRRepo})["repository"]
end


"""
    delete!(repo::ECRRepo)

Removes the passed `ECRRepo` instance from AWS ECR, and sets the `exists` attribute to `false` to
indicate it no longer exists.
"""
function delete!(repo::ECRRepo)
  repo.exists || error("Repo does not exist")
  delete_script = get_delete_ecr_repo_script(repo.repositoryName)
  run(`bash -c $delete_script`)
  repo.exists = false
end

