using Scratch

function use_scratch_space(what_to_write::String)::String
  scratch_dir = @get_scratch!("temp_scratch")
  scratch_fpath = joinpath(scratch_dir, "scratchfile")
  @show scratch_fpath
  open(scratch_fpath, "w") do f
    write(f, what_to_write)
  end
  "read: " * open(f->read(f, String), scratch_fpath)
end
