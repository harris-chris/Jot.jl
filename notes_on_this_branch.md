The bootstrap script:
alias Julia first, it's /user/local/julia/bin/julia on the docker image
RIE runs on 8080 by default
Running the bootstrap script with --trace-compile gets us a load of precompile statements for jot.
Running the tests for the package in question should do the same, I'm pretty sure we can just concatenate them both together.
The script to start the bootstrap doesn't need to be a full script, can just `run` from within julia.
We need a separate function in `Scripts.jl` to just grab the Julia start script, turn that into a separate script. Or make it a macro or something.

Create a test with a custom function argument, ie a struct defined in that module

What I think we want to do here:
- Before even creating a local image:
  - Run a julia script which starts the runtime locally and runs the function
  - This script should use --trace_compile to get all the precompile statements
  - We can then use `precompile_statements_file` for the sysimage
  - This should still be platform-agnostic
  - This script will have to be started via AWS RIE, see example in `get_bootstrap_script`
  - The bootstrap script is actually a bash script, need to add the --trace_compile onto that

Some potential problems:
- Packagecompiler seems to be writing the package compile file to `/tmp`, it's actually writing it to $SYSIMAGE_PATH, not sure where that's coming from
- The package-compile script is starting Jot async but it looks like Jot may not be up and running before the relevant bits of the package-compile script

There are a couple of scripts here that are useful for observing performance:

- `performance_test_script.jl` creates a couple of new lambda functions (one compiled using package-compiler, one not) and runs them repeatedly to compare performance. It can be run directly with `julia performance_test_script.jl`

- `create_random_function.jl` creates a new lambda function each time the script is run. It then runs this function and shows the log output for it.

My observations so far:
- There seems to be three states that a given function can be in:
  - Cold (container not started, function/Jot are not compiled). Takes about 16000 ms to run the function if cold.
  - Warm (container appears to be running, but the function/Jot still needs to compile). Takes about 8000ms to run the function if warm.
  - Hot (the container is running, and the function has already compiled). Takes about 2ms to run the function if hot.

The cold vs hot states make sense to me, but I'm not sure what's going on with the warm state.
