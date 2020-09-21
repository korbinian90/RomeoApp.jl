# RomeoApp

[![Build Status](https://travis-ci.com/korbinian90/RomeoApp.jl.svg?branch=master)](https://travis-ci.com/korbinian90/RomeoApp.jl)
[![Build Status](https://ci.appveyor.com/api/projects/status/github/korbinian90/RomeoApp.jl?svg=true)](https://ci.appveyor.com/project/korbinian90/RomeoApp-jl)
[![Codecov](https://codecov.io/gh/korbinian90/RomeoApp.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/korbinian90/RomeoApp.jl)
[![Coveralls](https://coveralls.io/repos/github/korbinian90/RomeoApp.jl/badge.svg?branch=master)](https://coveralls.io/github/korbinian90/RomeoApp.jl?branch=master)

Easy way to apply ROMEO unwrapping in the command line without Julia programming experience. This repository is a wrapper of [ROMEO.jl](https://github.com/korbinian90/ROMEO.jl).

Another possibility without requiring a Julia installation is the compiled version under [ROMEO](https://github.com/korbinian90/ROMEO).

Please cite [ROMEO bioRxiv](https://www.biorxiv.org/content/10.1101/2020.07.24.214551v1.abstract) if you use it! The link will update to the peer reviewed version after it is published.

## Getting Started

1. Install Julia

   Please install Julia using the binaries from this page https://julialang.org. (Julia 1.5 or newer is required, some package managers install outdated versions)

2. Install RomeoApp

   Start Julia (Type julia in the command line or start the installed Julia executable)

   Type the following in the Julia REPL:
   ```julia
   julia> ] # Be sure to type the closing bracket via the keyboard
   # Enters the Julia package manager
   (@v1.5) pkg> add https://github.com/korbinian90/RomeoApp.jl
   # All dependencies are installed automatically
   ```

3. Usage in Julia REPL

   ```julia
   julia> using RomeoApp
   julia> args = "phase.nii -m mag.nii -t [2.1,4.2,6.3] -o /tmp"
   julia> unwrapping_main(split(args))
   ```

4. Command line usage

   Copy the file `romeo.jl` to a convenient location. Open a command line in the calculation folder. An alias for `romeo` as `julia <path-to-file>/romeo.jl` might be convenient.
   ```
      $ julia <path-to-file>/romeo.jl phase.nii -m mag.nii -t [2.1,4.2,6.3] -o results
   ```

5. Help

   Calling the Julia script without arguments (or --help) displays all options.
   ```
      $ julia <path-to-file>/romeo.jl
   ```

## License
This project is licensed under the MIT License - see the [LICENSE](https://github.com/korbinian90/ROMEO.jl/blob/master/LICENSE) for details
