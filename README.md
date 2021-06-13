# Jot

what's the difference between create_ecr_repo and push_to_ecr? One creates the repo, the other pushes the image to it

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
