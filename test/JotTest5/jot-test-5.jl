using Scratch

function use_scratch_space(what_to_write::String)
    scratch_dir = @get_scratch!("temp_scratch")
    open("scratchfile", "w") do f
      write(f, what_to_write)
    end
    open(f->read(f, String), "scratchfile")
end
