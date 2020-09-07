using RomeoApp
using Test

@testset "ROMEO function tests" begin

p = joinpath("data", "small")
phasefile = joinpath(p, "Phase.nii")
phasefile_nan = joinpath(p, "phase_with_nan.nii")
magfile = joinpath(p, "Mag.nii")

function test_romeo(args)
    folder = tempname()
    args = [args..., "-o", folder]
    try
        msg = unwrapping_main(args)
        @test msg == 0
        @test isfile(joinpath(folder, "unwrapped.nii"))
    catch e
        println(args)
        println(sprint(showerror, e, catch_backtrace()))
    end
end

configurations = [
    [phasefile],
    [phasefile_nan],
    [phasefile, "-v"],
    [phasefile, "-g"],
    [phasefile, "-m", magfile],
    [phasefile, "-N"],
    [phasefile, "-i"],
    [phasefile, "-q"],
    [phasefile, "-Q"],
    [phasefile, "-e", "1:2"],
    [phasefile, "-e", "[1,3]"],
    [phasefile, "-e", "[1, 3]"], # fine here but not in command line
    [phasefile, "-k", "nomask"],
    [phasefile, "-t", "[2,4,6]"],
    [phasefile, "-t", "2:2:6"],
    [phasefile, "-t", "[2.1,4.2,6.3]"],
    [phasefile, "-w", "romeo"],
    [phasefile, "-w", "bestpath"],
    [phasefile, "-w", "1010"],
    [phasefile, "-T", "4"],
    [phasefile, "-B", "-t", "[2,4,6]"],
    [phasefile, "-B", "-t", "[2, 4, 6]"],
    [phasefile, "-s", "50"],
    [phasefile, "-s", "50", "--merge-regions"],
    [phasefile, "-s", "50", "--merge-regions", "--correct-regions"],
    [phasefile, "--wrap-addition", "0.1"],
    [phasefile, "--temporal-uncertain-unwrapping"],
]

for args in configurations
    test_romeo(args)
end

end

## help message
println()
unwrapping_main([])
