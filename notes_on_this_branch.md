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
