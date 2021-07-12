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
phasefile_1arreco = joinpath(tmpdir, "Phase.nii")
magfile_1arreco = joinpath(tmpdir, "Mag.nii")
savenii(niread(phasefile)[:,:,:,1], phasefile_1eco)
savenii(niread(magfile)[:,:,:,1], magfile_1eco)
savenii(niread(phasefile)[:,:,:,[1]], phasefile_1arreco)
savenii(niread(magfile)[:,:,:,[1]], magfile_1arreco)

phasefile_5D = joinpath(tmpdir, "phase_multi_channel.nii")
magfile_5D = joinpath(tmpdir, "mag_multi_channel.nii")
savenii(repeat(niread(phasefile),1,1,1,1,2), phasefile_5D)
savenii(repeat(niread(magfile),1,1,1,1,2), magfile_5D)

function test_romeo(args)
    folder = tempname()
    args = [args..., "-o", folder, "-v"]
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

configurations(phasefile, magfile) = vcat(configurations.([[phasefile], [phasefile, "-m", magfile]])...)
configurations(pm) = [
    [pm...],
    [pm..., "-g"],
    [pm..., "-N"],
    [pm..., "-i"],
    [pm..., "-q"],
    [pm..., "-Q"],
    [pm..., "-m", magfile, "-u"],
    [pm..., "-w", "romeo"],
    [pm..., "-w", "bestpath"],
    [pm..., "-w", "1010"],
    [pm..., "--threshold", "4"],
    [pm..., "-s", "50"],
    [pm..., "-s", "50", "--merge-regions"],
    [pm..., "-s", "50", "--merge-regions", "--correct-regions"],
    [pm..., "--wrap-addition", "0.1"],
    [pm..., "-k", "robustmask"],
    [pm..., "-k", "nomask"],
    [pm..., "-k", "qualitymask"],
]
configurations_me(phasefile, magfile) = vcat(configurations_me.([[phasefile], [phasefile, "-m", magfile]])...)
configurations_me(pm) = [
    [pm..., "-e", "1:2"],
    [pm..., "-e", "[1,3]"],
    [pm..., "-e", "[1", "3]"],
    [pm..., "-t", "[2,4,6]"],
    [pm..., "-t", "2:2:6"],
    [pm..., "-t", "[2.1,4.2,6.3]"],
    [pm..., "-B", "-t", "[2,4,6]"],
    [pm..., "-B", "-t", "[2" ,"4", "6]"], # when written like [2 4 6] in command line
    [pm..., "--temporal-uncertain-unwrapping"],
    [pm..., "--template", "1"],
    [pm..., "--template", "3"],
    [pm..., "--phase-offset-correction", "-t", "[2,4,6]"],
    [pm..., "--phase-offset-correction", "bipolar", "-t", "[2,4,6]", "-v"],
]

files = [(phasefile, magfile), (phasefile_1eco, magfile_1eco), (phasefile_1arreco, magfile_1arreco), (phasefile_1eco, magfile_1arreco), (phasefile_1arreco, magfile_1eco)]
for (pf, mf) in files, args in configurations(pf, mf)
    test_romeo(args)
end
for args in configurations_me(phasefile, magfile)
    test_romeo(args)
end
for args in configurations_me(phasefile_5D, magfile_5D)[end-1:end]
    test_romeo(args)
end
files_se = [(phasefile_1eco, magfile_1eco), (phasefile_1arreco, magfile_1arreco)]
for (pf, mf) in files_se
    b_args = ["-B", "-t", "3.06"]
    test_romeo(["-p", pf, b_args...])
    test_romeo(["-p", pf, "-m", mf, b_args...])
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

## print version to verify
println()
unwrapping_main(["--version"])
