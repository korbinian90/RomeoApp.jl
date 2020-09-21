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
        @test "test failed" == "with error" # signal a failed test
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
    [phasefile, "--threshold", "4"],
    [phasefile, "-B", "-t", "[2,4,6]"],
    [phasefile, "-B", "-t", "[2, 4, 6]"],
    [phasefile, "-s", "50"],
    [phasefile, "-s", "50", "--merge-regions"],
    [phasefile, "-s", "50", "--merge-regions", "--correct-regions"],
    [phasefile, "--wrap-addition", "0.1"],
    [phasefile, "--temporal-uncertain-unwrapping"],
    [phasefile, "--template", "1"],
    [phasefile, "--template", "3"],
    [phasefile, "--phase-offset-correction", "-t", "[2,4,6]"],
    [phasefile, "-m", magfile, "--phase-offset-correction", "-t", "[2,4,6]"],
]

for args in configurations
    test_romeo(args)
end

## test no-rescale
readphase = RomeoApp.readphase
phasefile_uw = joinpath(tempname(), "unwrapped.nii")
phasefile_uw_wrong = joinpath(tempname(), "wrong_unwrapped.nii")
phasefile_uw_again = joinpath(tempname(), "again_unwrapped.nii")
unwrapping_main([phasefile, "-o", phasefile_uw])
unwrapping_main([phasefile_uw, "-o", phasefile_uw_wrong])
unwrapping_main([phasefile_uw, "-o", phasefile_uw_again, "--no-rescale"])

@test readphase(phasefile_uw_again; rescale=false).raw == readphase(phasefile_uw; rescale=false).raw
@test readphase(phasefile_uw_wrong; rescale=false).raw != readphase(phasefile_uw; rescale=false).raw

end

## help message
println()
unwrapping_main([])
