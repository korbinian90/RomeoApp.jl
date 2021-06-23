function getargs(args::AbstractVector)
    if isempty(args)
        args = ["--help"]
    else
        if !('-' in args[1]) prepend!(args, Ref("-p")) end # if phase is first without -p
        if length(args) >= 2 && !("-p" in args || "--phase" in args) && !('-' in args[end-1]) # if phase is last without -p
            insert!(args, length(args), "-p")
        end
    end
    s = ArgParseSettings(
        exc_handler=exception_handler,
        add_version=true,
        version="v3.2.0",
        )
    @add_arg_table! s begin
        "--phase", "-p"
            help = "The phase image used for unwrapping"
        "--magnitude", "-m"
            help = "The magnitude image (better unwrapping if specified)"
        "--output", "-o"
            help = "The output path or filename"
            default = "unwrapped.nii"
        "--echo-times", "-t"
            help = """The relative echo times required for temporal unwrapping 
                specified in array or range syntax (eg. "[1.5,3.0]" or 
                "3.5:3.5:14"). (default is ones(<nr_of_time_points>) for 
                multiple volumes with the same time)"""
            nargs = '+'
        "--mask", "-k"
            help = "nomask | robustmask | <mask_file>"
            default = "robustmask"
        "--mask-unwrapped", "-u"
            help = """Apply the mask on the unwrapped result. If mask is 
                "nomask", sets it to "robustmask"."""
            action = :store_true
        "--unwrap-echoes", "-e"
            help = "Load only the specified echoes from disk"
            default = [":"]
            nargs = '+'
        "--weights", "-w"
            help = """romeo | romeo2 | romeo3 | romeo4 | bestpath |
                <4d-weights-file> | <flags>.
                <flags> are four bits to activate individual weights
                (eg. "1010"). The weights are (1)phasecoherence
                (2)phasegradientcoherence (3)phaselinearity (4)magcoherence"""
            default = "romeo"
        "--compute-B0", "-B"
            help = """Calculate combined B0 map in [Hz]. Phase offset
                correction might be necessary if not coil-combined with
                MCPC3Ds/ASPIRE."""
            action = :store_true
        "--phase-offset-correction"
            help = """on | off | bipolar.
                Applies the MCPC3Ds method to perform phase offset
                determination and removal (for multi-echo). This option also
                allows 5D input, where the 5th dimension is channels. "bipolar"
                removes eddy current artefacts (requires >= 3 echoes)."""
            default = "off"
            nargs = '?'
            constant = "on"
        "--individual-unwrapping", "-i"
            help = """Unwraps the echoes individually (not temporal).
                This might be necessary if there is large movement
                (timeseries) or phase-offset-correction is not
                applicable."""
            action = :store_true
        "--template"
            help = """Template echo that is spatially unwrapped and used for
                temporal unwrapping"""
            arg_type = Int
            default = 2
        "--no-mmap", "-N"
            help = """Deactivate memory mapping. Memory mapping might cause
                problems on network storage"""
            action = :store_true
        "--no-rescale"
            help = """Deactivate rescaling of input images. By default the
                input phase is rescaled to the range [-π;π]. This option
                allows inputting already unwrapped phase images without
                manually wrapping them first."""
            action = :store_true
        "--threshold"
            help = """<maximum number of wraps>.
                Threshold the unwrapped phase to the maximum number of wraps
                and sets exceeding values to 0"""
            arg_type = Float64
            default = Inf
        "--verbose", "-v"
            help = "verbose output messages"
            action = :store_true
        "--correct-global", "-g"
            help = """Phase is corrected to remove global n2π phase offset. The
                median of phase values (inside mask if given) is used to
                calculate the correction term"""
            action = :store_true
        "--write-quality", "-q"
            help = """Writes out the ROMEO quality map as a 3D image with one
                value per voxel"""
            action = :store_true
        "--write-quality-all", "-Q"
            help = """Writes out an individual quality map for each of the
                ROMEO weights."""
            action = :store_true
        "--max-seeds", "-s"
            help = """EXPERIMENTAL! Sets the maximum number of seeds for
                unwrapping. Higher values allow more seperated regions."""
            arg_type = Int
            default = 1
        "--merge-regions"
            help = """EXPERIMENTAL! Spatially merges neighboring regions after
                unwrapping."""
            action = :store_true
        "--correct-regions"
            help = """EXPERIMENTAL! Performed after merging. Brings the median
                of each region closest to 0 (mod 2π)."""
            action = :store_true
        "--wrap-addition"
            help = """[0;π] EXPERIMENTAL! Usually the true phase difference of
                neighboring voxels cannot exceed π to be able to unwrap
                them. This setting increases the limit and uses 'linear
                unwrapping' of 3 voxels in a line. Neighbors can have
                (π + wrap-addition) phase difference."""
            arg_type = Float64
            default = 0.0
        "--temporal-uncertain-unwrapping"
            help = """EXPERIMENTAL! Uses spatial unwrapping on voxels that have
                high uncertainty values after temporal unwrapping."""
            action = :store_true

    end
    return parse_args(args, s)
end

function exception_handler(settings::ArgParseSettings, err, err_code::Int=1)
    if err == ArgParseError("too many arguments")
        println(stderr,
            """Wrong argument formatting!
            Maybe there are unsupported spaces"""
        )
    end
    ArgParse.default_handler(settings, err, err_code)
end

function getechoes(settings, neco)
    echoes = eval(Meta.parse(join(settings["unwrap-echoes"], " ")))
    if echoes isa Int
        echoes = [echoes]
    elseif echoes isa Matrix
        echoes = echoes[:]
    end
    echoes = (1:neco)[echoes] # expands ":"
    if (length(echoes) == 1) echoes = echoes[1] end
    return echoes
end

function getTEs(settings, neco, echoes)
    TEs = if !isempty(settings["echo-times"])
            eval(Meta.parse(join(settings["echo-times"], " ")))
        else
            ones(neco)
        end 
    if TEs isa Matrix
        TEs = TEs[:]
    end
    if length(TEs) == neco
        TEs = TEs[echoes]
    end
    return TEs
end

function parseweights(settings)
    if isfile(settings["weights"]) && splitext(settings["weights"])[2] != ""
        return UInt8.(niread(settings["weights"]))
    else
        try
            reform = "Bool[$(join(collect(settings["weights"]), ','))]"
            flags = falses(6)
            flags[1:4] = eval(Meta.parse(reform))
            return flags
        catch
            return Symbol(settings["weights"])
        end
    end
end

function saveconfiguration(writedir, settings, args)
    writedir = abspath(writedir)
    open(joinpath(writedir, "settings_romeo.txt"), "w") do io
        for (fname, val) in settings
            if !(typeof(val) <: AbstractArray)
                println(io, "$fname: " * string(val))
            end
        end
        println(io, """Arguments: $(join(args, " "))""")
    end
end
