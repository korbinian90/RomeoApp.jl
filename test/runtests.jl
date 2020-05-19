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
    @test unwrapping_main(args) == 0
    @test isfile(joinpath(folder, "unwrapped.nii"))
end

configurations = [
    [phasefile],
    [phasefile_nan],
    [phasefile, "-v"],
    [phasefile, "-g"],
    [phasefile, "-m", magfile],
    [phasefile, "-N"],
    [phasefile, "-i"],
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
]

for args in configurations
    test_romeo(args)
end

end

## help message
println()
unwrapping_main([])
