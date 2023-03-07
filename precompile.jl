using Jot
using append_string_package
using HTTP
using Pkg

try
  Pkg.test("append_string_package")
catch e
  isa(e, LoadError) && rethrow(e)
end

rf(i::Int64) = i + 1

# This will error because we haven't started AWS RIE
try
  Jot.start_runtime("127.0.0.1:9001", rf, Int64; single_shot=true)
catch e
  isa(e, HTTP.ExceptionRequest.StatusError) || rethrow(e)
end
