function unwrapping_main(args)
    settings = getargs(args)

    writedir = settings["output"]
    filename = "unwrapped"
    if occursin(r"\.nii$", writedir)
        filename = basename(writedir)
        writedir = dirname(writedir)
    end

    if settings["magnitude"] == nothing && settings["weights"] == "romeo3"
        settings["weights"] = "romeo"
    end

    mkpath(writedir)
    saveconfiguration(writedir, settings, args)

    phasenii = readphase(settings["phase"], mmap=!settings["no-mmap"])
    hdr = header(phasenii)
    neco = size(phasenii, 4)

    echoes = try
        getechoes(settings, neco)
    catch y
        if isa(y, BoundsError)
            error("echoes=$(settings["unwrap-echoes"]): specified echo out of range! Number of echoes is $neco")
        else
            error("echoes=$(settings["unwrap-echoes"]) wrongly formatted!")
        end
    end

    phase = phasenii[:,:,:,echoes]
    phasenii = nothing

    keyargs = Dict()
    if settings["magnitude"] != nothing
        keyargs[:mag] = view(readmag(settings["magnitude"], mmap=!settings["no-mmap"]).raw,:,:,:,echoes)
        if size(keyargs[:mag]) != size(phase)
            error("size of magnitude and phase does not match!")
        end
    end

    ## get settings
    if isfile(settings["mask"])
        keyargs[:mask] = niread(settings["mask"]) .!= 0
        if size(keyargs[:mask]) != size(phase)[1:3]
            error("size of mask is $(size(keyargs[:mask])), but it should be $(size(phase)[1:3])!")
        end
    elseif settings["mask"] == "robustmask" && haskey(keyargs, :mag)
        keyargs[:mask] = robustmask(keyargs[:mag][:,:,:,1])
        savenii(keyargs[:mask], "mask", writedir, hdr)
    end
    if length(echoes) > 1
        keyargs[:TEs] = getTEs(settings, neco, echoes)
    end
    if isfile(settings["weights"]) && splitext(settings["weights"])[2] != ""
        keyargs[:weights] = UInt8.(niread(settings["weights"]))
    else
        keyargs[:weights] = Symbol(settings["weights"])
    end

    ## Error messages
    if 1 < length(echoes) && length(echoes) != length(keyargs[:TEs])
        error("Number of chosen echoes is $(length(echoes)) ($neco in .nii data), but $(length(keyargs[:TEs])) TEs were specified!")
    end

    if settings["correct-global"]
        keyargs[:correctglobal] = true
    end

    if settings["individual-unwrapping"] && length(echoes) > 1
        settings["verbose"] && println("perform individual unwrapping...")
        unwrap_individual!(phase; keyargs...)
    else
        settings["verbose"] && println("perform unwrapping...")
        unwrap!(phase; keyargs...)
    end
    settings["verbose"] && println("unwrapping finished!")

    if settings["threshold"] != Inf
        max = settings["threshold"] * 2π
        phase[phase .> max] .= 0
        phase[phase .< -max] .= 0
    end

    savenii(phase, filename, writedir, hdr)

    if settings["compute-B0"]
        if settings["echo-times"] == nothing
            error("echo times are required for B0 calculation! Unwrapping has been performed")
        end
        if !haskey(keyargs, :mag)
            keyargs[:mag] = ones(1,1,1,size(phase,4))
        end
        TEs = reshape(keyargs[:TEs],1,1,1,:)
        B0 = 1000 * sum(phase .* keyargs[:mag]; dims=4)
        B0 ./= sum(keyargs[:mag] .* TEs; dims=4)

        savenii(B0, "B0", writedir, hdr)
    end

    return 0
end
