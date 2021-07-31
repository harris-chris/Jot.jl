"""
    mutable struct AWSConfig
        account_id::Union{Missing, String} = missing
        region::Union{Missing, String} = missing
    end

Defines the Amazon Web Services account id and region to use.

Your current AWS CLI profile should match the account id specified here. To check that this is the
case, run `aws sts get-caller-identity --query Account --output text` from the command line. To 
see available profiles, run `aws configure list-profiles`.
"""
@with_kw mutable struct AWSConfig
  account_id::Union{Missing, String} = missing
  region::Union{Missing, String} = missing
end
StructTypes.StructType(::Type{AWSConfig}) = StructTypes.Mutable()  

function get_aws_config()::AWSConfig
  AWSConfig(
            readchomp(`aws sts get-caller-identity --query Account --output text`),
            readchomp(`aws configure get region`)
           )
end

@with_kw mutable struct AWSRolePolicyStatement
  Effect::Union{Missing, String} = missing
  Principal::Union{Missing, Dict{String, Any}} = missing
  Action::Union{Missing, String} = missing
end
StructTypes.StructType(::Type{AWSRolePolicyStatement}) = StructTypes.Mutable()  
Base.:(==)(a::AWSRolePolicyStatement, b::AWSRolePolicyStatement) = (
  a.Effect == b.Effect && a.Principal == b.Principal && a.Action == b.Action)

@with_kw mutable struct AWSRolePolicyDocument
  Version::Union{Missing, String} = missing
  Statement::Vector{AWSRolePolicyStatement} = Vector{AWSRolePolicyStatement}()
end
StructTypes.StructType(::Type{AWSRolePolicyDocument}) = StructTypes.Mutable()  
Base.:(==)(a::AWSRolePolicyDocument, b::AWSRolePolicyDocument) = (a.Version == b.Version && a.Statement == b.Statement)

@with_kw mutable struct AWSRole
  Path::Union{Missing, String} = missing
  RoleName::Union{Missing, String} = missing
  RoleId::Union{Missing, String} = missing
  Arn::Union{Missing, String} = missing
  CreateDate::Union{Missing, String} = missing
  AssumeRolePolicyDocument::Union{Missing, AWSRolePolicyDocument} = missing
  MaxSessionDuration::Union{Missing, Int64} = missing
  exists::Bool = true
end
StructTypes.StructType(::Type{AWSRole}) = StructTypes.Mutable()  
Base.:(==)(a::AWSRole, b::AWSRole) = a.RoleId == b.RoleId

const lambda_execution_policy_statement = AWSRolePolicyStatement(
    Effect = "Allow",
    Principal = Dict("Service" => "lambda.amazonaws.com"),
    Action = "sts:AssumeRole",
  )

"""
    function get_all_aws_roles()::Vector{AWSRole}
Get all AWS roles from the current AWS Config.
"""
function get_all_aws_roles()::Vector{AWSRole}
  all_roles_json = readchomp(`aws iam list-roles`)
  all = JSON3.read(all_roles_json, Dict{String, Vector{AWSRole}})
  all["Roles"]
end

"""
    function get_aws_role(role_name::String)::Union{Nothing, AWSRole}
Get the AWS Role corresponding to the given role_name. Returns nothing if none found.
"""
function get_aws_role(role_name::String)::Union{Nothing, AWSRole}
  all = get_all_aws_roles()
  index = findfirst(role -> role.RoleName == role_name, all)
  isnothing(index) ? nothing : all[index]
end

"""
    function create_aws_role(role_name::String)::AWSRole

Create an AWS Role with Lambda execution permissions.
"""
function create_aws_role(role_name::String)::AWSRole
  existing_role = get_aws_role(role_name) 
  @debug role_name
  @debug existing_role
  if !isnothing(existing_role)
    if aws_role_has_lambda_execution_permissions(existing_role)
      existing_role
    else
      error("Existing role with name $role_name exists, but does not have execution permissions")
    end
  else
    create_script = get_create_lambda_role_script(role_name)
    role_json = readchomp(`bash -c $create_script`)
    @info "Creating role $role_name ..."
    sleep(7);
    JSON3.read(role_json, Dict{String, AWSRole})["Role"]
  end
end

"""
    function delete!(role::AWSRole)

Delete an AWS Role. The role itself will be deleted from AWS, and the `AWSRole` type will no longer
be usable.
"""
function delete!(role::AWSRole)
  role.exists || error("Role does not exist")
  delete_script = get_delete_lambda_role_script(role.RoleName)
  run(`bash -c $delete_script`)
  role.exists = false
end

function get_role_arn_string(
    aws_config::AWSConfig, 
    role_name::String,
  )::String
  "arn:aws:iam::$(aws_config.account_id):role/$role_name"
end

function get_function_uri_string(aws_config::AWSConfig, function_name::String)::String
  "$(aws_config.account_id).dkr.ecr.$(aws_config.region).amazonaws.com/$function_name"
end

function get_function_arn_string(aws_config::AWSConfig, function_name::String)::String
  "arn:aws:lambda:$(aws_config.region):$(aws_config.account_id):function:$function_name"
end

function get_ecr_arn_string(aws_config::AWSConfig, image_suffix::String)::String
  "arn:aws:ecr:$(aws_config.region):$(aws_config.account_id):repository/$image_suffix"
end

function get_ecr_uri_string(aws_config::AWSConfig, image_suffix::String)::String
  "$(aws_config.account_id).dkr.ecr.$(aws_config.region).amazonaws.com/$image_suffix"
end

function create_lambda_execution_role(role_name)
  create_script = get_create_lambda_role_script(role_name)
  run(`bash -c $create_script`)
end

function aws_role_has_lambda_execution_permissions(role::AWSRole)::Bool
  lambda_execution_policy_statement in role.AssumeRolePolicyDocument.Statement 
end

