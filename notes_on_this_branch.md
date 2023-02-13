! multi-to argument for tests is not working
! set JULIA_LOAD_PATH=@ in the nix shell so that only Jot's packages can be used.
! Have a throw_away_first argument for `create_lambda_function`. Or maybe `test_on_creation`. Because the first function run is not representative in terms of timing.
! Does it still work without FunctionTestData? There are three scenarios - no FunctionTestData, FunctionTestData but no compile, FunctionTestData with compile. Add test for this.
! Have a way to keep the build dir, maybe specify where it will go and if so keep it; or go the other way and get everything being done within the Dockerfile. Having the scripts generated locally and ten called from the dockerfile seems reasonable, although less visibility of them when they're running in the docker output. Maybe read the scripts, then replace \n => ;, and put them in the dockerfile output like that.
! read jot_github_url from the .git directory?
! Think about the simplest possible flow, like:
  - Everything relates back to the `get_dockerfile` function
! redirect_stdio bumps our required julia version to 1.7
! prog = ProgressUnknown("Working hard:", spinner=true) to get a spinner
! grep for all references for jot_temp
! Believe that the point at which these packages are being made part of Jot is when you do Pkg.develop() in the single_run_launcher for package compile, but can't see a way to make this only temporary. Unless having it all run in a temp directory is enough for that.

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

There are a couple of scripts here that are useful for observing performance:

- `performance_test_script.jl` creates a couple of new lambda functions (one compiled using package-compiler, one not) and runs them repeatedly to compare performance. It can be run directly with `julia performance_test_script.jl`

- `create_random_function.jl` creates a new lambda function each time the script is run. It then runs this function and shows the log output for it.

