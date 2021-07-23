What should this look like?
- function name
- then boxes indicating whether they exist - 

Can we get the function name from the lambda function alone?
Should the image name be made into the repository name?

matches for 

What is the general identifier here? Module.response_function

then Responder/location (blank if the local directory hash does not match the responder)
then Local image (image id, blank if none)
then Remote image (digest, blank if none)
then Lambda Function (name, blank if none)

Responder -> identifier easy
Local image -> identifier via environment variables

this relies on us being able to recover the general identifier from all components

made Labels a struct

delete remoteimage by id

COPY . . -chown

add to guide:
    IOError(Base.IOError("read: connection reset by peer (ECONNRESET)", -104) during request(http://localhost:9000/2015-03-31/functions/function/invocations))

