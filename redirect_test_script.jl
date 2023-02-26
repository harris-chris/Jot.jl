stdout_buffer = IOBuffer()
@show stdout_buffer
stderr_buffer = IOBuffer()
finished = Base.Event()
# cmd = run(`echo "starting"\; sleep\(5\)\; echo "finished"`) #; stdout=stdout_buffer, stderr=stderr_buffer)
cd("jot_temp") do
  cmd = pipeline(`sh single_run_launcher.jl`; stdout=stdout_buffer, stderr=stderr_buffer)
  # try
  p = open(cmd)
  @show p
  @show getpid(p)
  # catch e
  #   println("Caught error")
  #   # !isa(e, LoadError) && rethrow()
  # end
end
@info "Now checking"
while true
  if occursin("start_runtime", String(take!(stdout_buffer)))
    break
  end
  sleep(1)
end
@info "Found start thing"

# for n=1:7
#   @show stdout_buffer
#   @show read(stdout_buffer)
#   @show read(stderr_buffer)
#   sleep(1)
# end
# println("Finished notification")
# println("Stdout buffer")
# println(read(stdout_buffer))
# println("Stderr buffer")
# println(read(stderr_buffer))
# wait(finished)
# open(`sh jot_temp/single_run_launcher.jl`, stdio = stdout_buffer;

