module RomeoApp

using ArgParse
using MriResearchTools
using ROMEO

include("argparse.jl")
include("caller.jl")

function julia_main(version)::Cint
    try
        unwrapping_main(ARGS; version)
    catch
        Base.invokelatest(Base.display_error, Base.catch_stack())
        return 1
    end
    return 0
end

export unwrapping_main

end # module
