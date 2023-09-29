# RomeoApp [deprecated]
The functionality has moved to [ROMEO.jl as an extension](https://github.com/korbinian90/ROMEO.jl#usage---command-line).

---------------
Easy way to apply ROMEO unwrapping in the command line without Julia programming experience. This repository is a wrapper of [ROMEO.jl](https://github.com/korbinian90/ROMEO.jl).

Another possibility without requiring a Julia installation is the compiled version under [ROMEO](https://github.com/korbinian90/ROMEO).

Please cite [ROMEO MRM](https://doi.org/10.1002/mrm.28563) if you use it!

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
