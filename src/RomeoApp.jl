module RomeoApp

using ArgParse
using MriResearchTools
using ROMEO
using Statistics

include("argparse.jl")
include("caller.jl")

function julia_main()::Cint
    try
        unwrapping_main(ARGS)
    catch
        Base.invokelatest(Base.display_error, Base.catch_stack())
        return 1
    end
    return 0
end

export unwrapping_main

end # module
