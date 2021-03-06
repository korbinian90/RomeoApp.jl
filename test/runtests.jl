using RomeoApp
using Test

@testset "ROMEO function tests" begin

niread = RomeoApp.niread
savenii = RomeoApp.savenii

p = joinpath("data", "small")
phasefile = joinpath(p, "Phase.nii")
phasefile_nan = joinpath(p, "phase_with_nan.nii")
magfile = joinpath(p, "Mag.nii")
tmpdir = mktempdir()
phasefile_1eco = joinpath(tmpdir, "Phase.nii")
magfile_1eco = joinpath(tmpdir, "Mag.nii")
savenii(niread(phasefile)[:,:,:,1], phasefile_1eco)
savenii(niread(magfile)[:,:,:,1], magfile_1eco)

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

configurations(phasefile, magfile) = [
    [phasefile],
    [phasefile, "-v"],
    [phasefile, "-g"],
    [phasefile, "-m", magfile],
    [phasefile, "-N"],
    [phasefile, "-i"],
    [phasefile, "-q"],
    [phasefile, "-Q"],
    [phasefile, "-u"],
    [phasefile, "-w", "romeo"],
    [phasefile, "-w", "bestpath"],
    [phasefile, "-w", "1010"],
    [phasefile, "--threshold", "4"],
    [phasefile, "-s", "50"],
    [phasefile, "-s", "50", "--merge-regions"],
    [phasefile, "-s", "50", "--merge-regions", "--correct-regions"],
    [phasefile, "--wrap-addition", "0.1"],
]
configurations_me(phasefile, magfile) = [
    [phasefile, "-e", "1:2"],
    [phasefile, "-e", "[1,3]"],
    [phasefile, "-e", "[1, 3]"], # fine here but not in command line
    [phasefile, "-k", "robustmask"],
    [phasefile, "-t", "[2,4,6]"],
    [phasefile, "-t", "2:2:6"],
    [phasefile, "-t", "[2.1,4.2,6.3]"],
    [phasefile, "-B", "-t", "[2,4,6]"],
    [phasefile, "-B", "-t", "[2, 4, 6]"],
    [phasefile, "--temporal-uncertain-unwrapping"],
    [phasefile, "--template", "1"],
    [phasefile, "--template", "3"],
    [phasefile, "--phase-offset-correction", "-t", "[2,4,6]"],
    [phasefile, "-m", magfile, "--phase-offset-correction", "-t", "[2,4,6]"],
]

for (pf, mf) in [(phasefile, magfile), (phasefile_1eco, magfile_1eco)], args in configurations(pf, mf)
    test_romeo(args)
end
for args in configurations_me(phasefile, magfile)
    test_romeo(args)
end
test_romeo([phasefile_nan])

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

## test quality map

unwrapping_main([phasefile, "-m", magfile, "-o", tmpdir, "-qQ"])
fns = joinpath.(tmpdir, ["quality.nii", ("quality_$i.nii" for i in 1:4)...])
@show fns
for i in 1:length(fns), j in i+1:length(fns)
    @test niread(fns[i]).raw != niread(fns[j]).raw
end

end

## help message
println()
unwrapping_main([])
