function getargs(args)
    if isempty(args) args = ["--help"] end
    s = ArgParseSettings(exc_handler=exception_handler)
    @add_arg_table! s begin
        "phase"
            help = "The phase image used for unwrapping"
        "--magnitude", "-m"
            help = "The magnitude image (better unwrapping if specified)"
        "--output", "-o"
            help = "The output path and filename"
            default = "unwrapped.nii"
        "--echo-times", "-t"
            help = """The relative echo times required for temporal unwrapping (default is 1:n)
                    specified in array or range syntax (eg. [1.5,3.0] or 2:5)
                    Warning: No spaces allowed!! ([1, 2, 3] is invalid!)"""
        "--mask", "-k"
            help = "nomask | robustmask | <mask_file>"
            default = "robustmask"
        "--individual-unwrapping", "-i"
            help = """Unwraps the echoes individually (not temporal)
                    Temporal unwrapping only works with ASPIRE"""
            action = :store_true
        "--unwrap-echoes", "-e"
            help = "Unwrap only the specified echoes"
            default = ":"
        "--weights", "-w"
            help = "romeo | bestpath | <4d-weights-file> "
            default = "romeo"
        "--compute-B0", "-B"
            help = "EXPERIMENTAL! Calculate combined B0 map in [rad/s]"
            action = :store_true
        "--no-mmap", "-N"
            help = """Deactivate memory mapping.
                    Memory mapping might cause problems on network storage"""
            action = :store_true
        "--threshold", "-T"
            help = """<maximum number of wraps>
                    Threshold the unwrapped phase to the maximum number of wraps
                    Sets exceeding values to 0"""
            arg_type = Float64
            default = Inf
    end
    return parse_args(args, s)
end

function exception_handler(settings::ArgParseSettings, err, err_code::Int=1)
    if err == ArgParseError("too many arguments")
        println(stderr, """Wrong argument formatting!
        Maybe there are unsupported spaces in the array syntax.
        [1, 2, 3] is wrong; [1,2,3] is correct
        """)
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
        @show TEs = eval(Meta.parse(settings["echo-times"]))
        if length(TEs) == neco
            TEs = TEs[echoes]
        end
    else
        TEs = (1:neco)[echoes]
    end
    return TEs
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
