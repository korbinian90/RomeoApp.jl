using RomeoApp
using Test

@testset "ROMEO function tests" begin

phasefile = joinpath("data", "small", "Phase.nii")
magfile = joinpath("data", "small", "Mag.nii")

function test_romeo(args)
    file = tempname()
    args = [args..., "-o", file]
    unwrapping_main(args)
    @test isfile(joinpath(file, "unwrapped.nii"))
end

args = [phasefile, "-B", "-t", "[2,4,6]"]
test_romeo(args)

args = [phasefile, "-m", magfile]
test_romeo(args)

end
