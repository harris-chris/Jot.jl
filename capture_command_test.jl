function execute(cmd::Cmd)
  out = Pipe()
  err = Pipe()

  process = run(pipeline(ignorestatus(cmd), stdout=out, stderr=err))
  close(out.in)
  close(err.in)

  (
    stdout = String(read(out)),
    stderr = String(read(err)),
    code = process.exitcode
  )
end

println("Executing ls")
execute(`ls`)
println("Executing ls invalid")
execute(`ls --invalid-option`)
