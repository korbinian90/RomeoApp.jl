using RomeoApp
using Test

@testset "ROMEO function tests" begin

niread = RomeoApp.niread
savenii = RomeoApp.savenii

p = joinpath("data", "small")
phasefile_me = joinpath(p, "Phase.nii")
phasefile_me_nan = joinpath(p, "phase_with_nan.nii")
magfile_me = joinpath(p, "Mag.nii")
tmpdir = mktempdir()
phasefile_me_1eco = joinpath(tmpdir, "Phase.nii")
magfile_1eco = joinpath(tmpdir, "Mag.nii")
phasefile_me_1arreco = joinpath(tmpdir, "Phase.nii")
magfile_1arreco = joinpath(tmpdir, "Mag.nii")
savenii(niread(phasefile_me)[:,:,:,1], phasefile_me_1eco)
savenii(niread(magfile_me)[:,:,:,1], magfile_1eco)
savenii(niread(phasefile_me)[:,:,:,[1]], phasefile_me_1arreco)
savenii(niread(magfile_me)[:,:,:,[1]], magfile_1arreco)

phasefile_me_5D = joinpath(tmpdir, "phase_multi_channel.nii")
magfile_5D = joinpath(tmpdir, "mag_multi_channel.nii")
savenii(repeat(niread(phasefile_me),1,1,1,1,2), phasefile_me_5D)
savenii(repeat(niread(magfile_me),1,1,1,1,2), magfile_5D)

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

configurations_se(pf, mf) = vcat(configurations_se.([[pf], [pf, "-m", mf]])...)
configurations_se(pm) = [
    [pm...],
    [pm..., "-g"],
    [pm..., "-N"],
    [pm..., "-i"],
    [pm..., "-q"],
    [pm..., "-Q"],
    [pm..., "-m", magfile_me, "-u"],
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
configurations_me(phasefile_me, magfile_me) = vcat(configurations_me.([[phasefile_me], [phasefile_me, "-m", magfile_me]])...)
configurations_me(pm) = [
    [pm..., "-e", "1:2", "-t", "[2,4]"], # giving two echo times for two echoes used out of three
    [pm..., "-e", "[1,3]", "-t", "[2,4,6]"], # giving three echo times for two echoes used out of three
    [pm..., "-e", "[1", "3]", "-t", "[2,4,6]"],
    [pm..., "-t", "[2,4,6]"],
    [pm..., "-t", "2:2:6"],
    [pm..., "-t", "[2.1,4.2,6.3]"],
    [pm..., "-t", "epi"], # shorthand for "ones(<num-echoes>)"
    [pm..., "-t", "epi", "5.3"], # shorthand for "5.3*ones(<num-echoes>)"
    [pm..., "-B", "-t", "[2,4,6]"],
    [pm..., "-B", "-t", "[2" ,"4", "6]"], # when written like [2 4 6] in command line
    [pm..., "--temporal-uncertain-unwrapping", "-t", "[2,4,6]"],
    [pm..., "--template", "1", "-t", "[2,4,6]"],
    [pm..., "--template", "3", "-t", "[2,4,6]"],
    [pm..., "--phase-offset-correction", "-t", "[2,4,6]"],
    [pm..., "--phase-offset-correction", "bipolar", "-t", "[2,4,6]"],
]
# TODO if no mag is given set default mask to qualitymask
files = [(phasefile_me_1eco, magfile_1eco), (phasefile_me_1arreco, magfile_1arreco), (phasefile_me_1eco, magfile_1arreco), (phasefile_me_1arreco, magfile_1eco)]
for (pf, mf) in files, args in configurations_se(pf, mf)
    test_romeo(args)
end
for args in configurations_me(phasefile_me, magfile_me)
    test_romeo(args)
end
for args in configurations_me(phasefile_me_5D, magfile_5D)[end-1:end]
    test_romeo(args)
end
files_se = [(phasefile_me_1eco, magfile_1eco), (phasefile_me_1arreco, magfile_1arreco)]
for (pf, mf) in files_se
    b_args = ["-B", "-t", "3.06"]
    test_romeo(["-p", pf, b_args...])
    test_romeo(["-p", pf, "-m", mf, b_args...])
end

test_romeo([phasefile_me_nan, "-t", "[2,4]", "-k", "nomask"])
m = "multi-echo data is used, but no echo times are given. Please specify the echo times using the -t option."
@test_throws ErrorException(m) unwrapping_main(["-p", phasefile_me, "-o", tmpdir, "-v"])

## test no-rescale
readphase = RomeoApp.readphase
phasefile_me_uw = joinpath(tempname(), "unwrapped.nii")
phasefile_me_uw_wrong = joinpath(tempname(), "wrong_unwrapped.nii")
phasefile_me_uw_again = joinpath(tempname(), "again_unwrapped.nii")
unwrapping_main([phasefile_me, "-o", phasefile_me_uw, "-t", "[2,4,6]"])
unwrapping_main([phasefile_me_uw, "-o", phasefile_me_uw_wrong, "-t", "[2,4,6]"])
unwrapping_main([phasefile_me_uw, "-o", phasefile_me_uw_again, "-t", "[2,4,6]", "--no-rescale"])

@test readphase(phasefile_me_uw_again; rescale=false).raw == readphase(phasefile_me_uw; rescale=false).raw
@test readphase(phasefile_me_uw_wrong; rescale=false).raw != readphase(phasefile_me_uw; rescale=false).raw

## test quality map

unwrapping_main([phasefile_me, "-m", magfile_me, "-o", tmpdir, "-t", "[2,4,6]", "-qQ"])
fns = joinpath.(tmpdir, ["quality.nii", ("quality_$i.nii" for i in 1:4)...])
@show fns
for i in 1:length(fns), j in i+1:length(fns)
    @test niread(fns[i]).raw != niread(fns[j]).raw
end

end

## print version to verify
println()
unwrapping_main(["--version"])
