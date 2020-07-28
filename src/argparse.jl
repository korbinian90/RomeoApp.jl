function getargs(args)
    if isempty(args) args = ["--help"] end
    s = ArgParseSettings(
        exc_handler=exception_handler,
        add_version=true,
        version="v2.0.2",
        )
    @add_arg_table! s begin
        "phase"
            help = "The phase image used for unwrapping"
        "--magnitude", "-m"
            help = "The magnitude image (better unwrapping if specified)"
        "--output", "-o"
            help = "The output path or filename"
            default = "unwrapped.nii"
        "--echo-times", "-t"
            help = """The relative echo times required for temporal unwrapping
                    (default is 1:n) specified in array or range syntax
                    (eg. "[1.5,3.0]" or "3.5:3.5:14") or for multiple volumes
                    with the same time: "ones(<nr_of_time_points>)".
                    Warning: No spaces allowed!! ("[1, 2, 3]" is invalid!)"""
        "--mask", "-k"
            help = "nomask | robustmask | <mask_file>"
            default = "robustmask"
        "--individual-unwrapping", "-i"
            help = """Unwraps the echoes individually (not temporal).
                    Temporal unwrapping only works when phase offset is removed
                    (ASPIRE)"""
            action = :store_true
        "--unwrap-echoes", "-e"
            help = "Unwrap only the specified echoes"
            default = ":"
        "--weights", "-w"
            help = """romeo | romeo2 | romeo3 | romeo4 | bestpath |
                <4d-weights-file> | <flags>.
                <flags> are four bits to activate individual weights
                (eg. "1010"). The weights are (1)phasecoherence
                (2)phasegradientcoherence (3)phaselinearity (4)magcoherence"""
            default = "romeo"
        "--compute-B0", "-B"
            help = "EXPERIMENTAL! Calculate combined B0 map in [rad/s]"
            action = :store_true
        "--no-mmap", "-N"
            help = """Deactivate memory mapping. Memory mapping might cause
                    problems on network storage"""
            action = :store_true
        "--threshold", "-T"
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

    end
    return parse_args(args, s)
end

function exception_handler(settings::ArgParseSettings, err, err_code::Int=1)
    if err == ArgParseError("too many arguments")
        println(stderr,
            """Wrong argument formatting!
            Maybe there are unsupported spaces in the array syntax
            [1, 2, 3] is wrong; [1,2,3] is correct"""
        )
    end
    ArgParse.default_handler(settings, err, err_code)
end

function getechoes(settings, neco)
    echoes = eval(Meta.parse(settings["unwrap-echoes"]))
    if typeof(echoes) <: Int
        echoes = [echoes]
    end
    echoes = (1:neco)[echoes]
    if length(echoes) == 1 echoes = echoes[1] end
    return echoes
end

function getTEs(settings, neco, echoes)
    if settings["echo-times"] != nothing
        TEs = eval(Meta.parse(settings["echo-times"]))
        if length(TEs) == neco
            TEs = TEs[echoes]
        end
    else
        TEs = (1:neco)[echoes]
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
    @show writedir
    open(joinpath(writedir, "settings_romeo.txt"), "w") do io
        for (fname, val) in settings
            if !(typeof(val) <: AbstractArray)
                println(io, "$fname: " * string(val))
            end
        end
        println(io, """Arguments: $(join(args, " "))""")
    end
end
