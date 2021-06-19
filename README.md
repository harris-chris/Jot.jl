# Jot

# WIP, please ignore this until ready

what's the difference between create_ecr_repo and push_to_ecr? One creates the repo, the other pushes the image to it

So far we have been defining Image etc structs as being purely text data, not storing any actual julia objects.
This has the advantage that we can instantiate them from docker/AWS output
But it creates a tricky situation for eg the comprehensive create_lambda_function function, because how then do we return the image/role to the user? And if not, how does the user delete these?
What should be the syntax for deleting these things?
Should the user maybe have a 'path' type object rather than a different object for each stage?
The path can include everything except the role
How would we reconstruct the path for an existing, say, image though? Without explicitly storing it?
I guess we might want something like a linked list
you could use the local image as the base, think everything else can be inferred from that

the docker hashes do seem to understand changes in file contents.
Also images do retain their historical contents, even if the file structure changes

I don't think we will be able to go from image -> ResponseFunction, because the historical ResponseFunction will no longer even exist.
But hashes should be reliable and images locally/remotely can be matched up well

We can query docker/aws to get the complete picture of what exists and where.
it can show a nice table of Jots

The default delete action should be to delete the entire jot. But you can also delete sections.
A jot should permit multiple versions/tags. We can just show the most recent one.
Note that tags and hashes are somewhat equivalent
Probably best to have a drop-down for various versions.
{
  "my-module.my-function": [
    "version": nothing,
    "localImage": {
      "repository":
      "tag":
  
my-function  ResponseFunction -> LocalImage ->   Repo ->   Functions  
              -> not current      ->0.1           ->0.1     ->earlyVersion1
              -> not current      ->0.1           ->0.1     ->earlyVersion2
              -> commit x83u2     ->0.2           ->0.2     ->midVersion
              -> HEAD/current     ->latest        ->latest  ->latest (but out-of-date; hashes do not match, so put in red)

HASHES
-------
can obtain git hash using readchomp(`git log --format=%H -1`) - this is the hash of the current commit, not the tree hash

LAMBDAS
--------
When capturing lambdas, we can filter by on-local or on-remote. Probably on-local by default.
At the moment, the response_function is an actual module (not a string). For this, probably best to represent it as a string.
But then how do we recover the root? What data do we actually extract from the module?
- the package name, the function name, the package path

Process for getting all lambdas:
- get all local images
- get all remote images
- get all functions
See which of these we can link together

Use 
`docker image ls` to get all local images
`aws ecr describe-repositories` to get all repos, but within that `aws ecr list-images` individually within these
`aws lambda list-functions` gets us all the functions, but then need to (individually) run
`aws lambda get-function --function-name=<x>` to find the repo associated with a function. ResolvedImageUri gives the hash.
Then try and line these up.
Start associating forwards or backwards? Actually what's the problem?

Vectorized?


Are we sure that we have a one-to-one mapping for all stages?
image -> repo => 

# Some sort of visual output showing what has been done so far

ResponseFunction -> Image -> Repo -> LambdaFunction
                                                         Role -> ?

Can path go both ways - can we discover image from responsefunction?
ResponseFunction -> 

ResponseFunction -> Image is hard. Have to inspect image layers. For the time being could just show when change was made.
Image -> Repo is probably easy. Check image last updated date vs repo last updated date. If image last updated date > repo last updated date, not the same.
Repo -> LambdaFunction is probably easy - similar system.

If this is always the case, retrieve this as a vector?

How to show that these have been tested?

show path with functions as argument? The functions are kind of a static feature of the path though
shell interop and exporting the scripts?

The repo can have multiple images in
- we need separate docker image and ecr image types

Add a validate_package function, because ResponseFunction is not being validated on instantiation if it is PackageName, FunctionName as strings.
Or, somehow validate ModuleDefinition on instantiation, maybe at least check the path and somehow check the names 
