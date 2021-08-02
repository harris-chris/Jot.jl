# Adding Labels to Jot objects

Both Docker and AWS have labelling/tagging features, which allow user-defined metadata to be attached to Local docker images, AWS ECR Repos, and AWS Lambda functions. Jot leverages these features to attach Jot-generated labels to resources generated via Jot, and allows user-defined labels to be added alongside these. These labels are key/value pairs and (by a limitation of AWS) both the key and the value must be strings.

User-defined labels can be set in the `create_local_image` function via the `user_defined_labels` keyword argument:

`create_local_image("my_lambda", my_responder; user_defined_labels = Dict("name" => "my_lambda"))`

They are then added to the underlying Docker image, and carried through to all subsequent Jot-generated resources (remote images hosted on AWS ECR, and lambda functions). The `get_user_labels` function can be used to recover these labels from their respective resources, eg:
```
local_image = get_local_image("my_lambda")
get_user_labels(local_image)

lambda_function = get_lambda_function("my_lambda")
get_user_labels(lambda_function)
```
