function unwrapping_main(args)
    settings = getargs(args)
    keyargs = Dict()
    
    writedir = settings["output"]
    filename = "unwrapped"
    if occursin(r"\.nii$", writedir)
        filename = basename(writedir)
        writedir = dirname(writedir)
    end

    if settings["weights"] == "romeo"
        if isnothing(settings["magnitude"])
            settings["weights"] = "romeo4"
        else
            settings["weights"] = "romeo3"
        end
    end

    if settings["mask-unwrapped"] && settings["mask"][1] == "nomask"
        settings["mask"][1] = "robustmask"
    end

    if settings["mask"][1] == "robustmask" && !haskey(keyargs, :mag)
        settings["mask"][1] = "qualitymask"
        @warn "robustmask was chosen but no magnitude is available. The mask is changed to qualitymask!"
    end

    mkpath(writedir)
    saveconfiguration(writedir, settings, args)

    phase = readphase(settings["phase"], mmap=!settings["no-mmap"], rescale=!settings["no-rescale"])
    hdr = header(phase)
    neco = size(phase, 4)

    ## Perform phase offset correction
    if settings["phase-offset-correction"] in ["on", "monopolar", "bipolar"]
        TEs = getTEs(settings, neco, :)
        if neco != length(TEs) && all(TEs .== 1) error("Phase offset determination requires all echo times!") end
        polarity = if settings["phase-offset-correction"] == "bipolar" "bipolar" else "monopolar" end
        settings["verbose"] && println("perform phase offset correction with MCPC3D-S ($polarity)")
        
        po = zeros(Complex{eltype(phase)}, (size(phase)[1:3]...,size(phase,5)))
        mag = if !isnothing(settings["magnitude"]) readmag(settings["magnitude"], mmap=!settings["no-mmap"]) else ones(size(phase)) end # TODO trues instead ones?
        bipolar_correction = settings["phase-offset-correction"] == "bipolar"
        phase, mcomb = mcpc3ds(phase, mag; TEs=TEs, po=po, bipolar_correction=bipolar_correction)
        if size(mag, 5) != 1
            keyargs[:mag] = mcomb
        end
        settings["verbose"] && println("Saving corrected_phase and phase_offset")
        savenii(phase, "corrected_phase", writedir, hdr)
        settings["verbose"] && savenii(angle.(po), "phase_offset", writedir, hdr)
    end

    ## Echoes for unwrapping
    echoes = try
        getechoes(settings, neco)
    catch y
        if isa(y, BoundsError)
            error("echoes=$(settings["unwrap-echoes"]): specified echo out of range! Number of echoes is $neco")
        else
            error("echoes=$(settings["unwrap-echoes"]) wrongly formatted!")
        end
    end
    settings["verbose"] && println("Echoes are $echoes")

    keyargs[:TEs] = getTEs(settings, neco, echoes)
    settings["verbose"] && println("TEs are $(keyargs[:TEs])")

    ## Error messages
    if 1 < length(echoes) && length(echoes) != length(keyargs[:TEs])
        error("Number of chosen echoes is $(length(echoes)) ($neco in .nii data), but $(length(keyargs[:TEs])) TEs were specified!")
    end
    
    phase = phase[:,:,:,echoes]
    settings["verbose"] && println("Phase loaded!")

    if !isnothing(settings["magnitude"]) && !haskey(keyargs, :mag)
        keyargs[:mag] = view(readmag(settings["magnitude"], mmap=!settings["no-mmap"]),:,:,:,echoes) # view avoids copy
        if size(keyargs[:mag]) != size(phase)
            error("size of magnitude and phase does not match!")
        end
        settings["verbose"] && println("Magnitude loaded!")
    end

    keyargs[:correctglobal] = settings["correct-global"]
    keyargs[:weights] = parseweights(settings)
    keyargs[:maxseeds] = settings["max-seeds"]
    settings["verbose"] && keyargs[:maxseeds] != 1 && println("Maxseeds are $(keyargs[:maxseeds])")
    keyargs[:merge_regions] = settings["merge-regions"]
    settings["verbose"] && keyargs[:merge_regions] && println("Region merging is activated")
    keyargs[:correct_regions] = settings["correct-regions"]
    settings["verbose"] && keyargs[:correct_regions] && println("Region correcting is activated")
    keyargs[:wrap_addition] = settings["wrap-addition"]
    keyargs[:temporal_uncertain_unwrapping] = settings["temporal-uncertain-unwrapping"]
    keyargs[:individual] = settings["individual-unwrapping"]
    settings["verbose"] && println("individual unwrapping is $(keyargs[:individual])")
    keyargs[:template] = settings["template"]
    settings["verbose"] && !settings["individual-unwrapping"] && println("echo $(keyargs[:template]) used as template")

    ## set mask
    if isfile(settings["mask"][1])
        settings["verbose"] && println("Trying to read mask from file $(settings["mask"])")
        keyargs[:mask] = niread(settings["mask"]).raw .!= 0
        if size(keyargs[:mask]) != size(phase)[1:3]
            error("size of mask is $(size(keyargs[:mask])), but it should be $(size(phase)[1:3])!")
        end
    elseif settings["mask"][1] == "robustmask" && haskey(keyargs, :mag)
        settings["verbose"] && println("Calculate robustmask from magnitude, saved as mask.nii")
        mag = keyargs[:mag]
        template_echo = min(keyargs[:template], size(mag, 4))
        keyargs[:mask] = robustmask(mag[:,:,:,template_echo])
        savenii(keyargs[:mask], "mask", writedir, hdr)
    elseif settings["mask"][1] == "qualitymask"
        threshold = if length(settings["mask"]) > 1
            settings["mask"][2]
        else
            0.5 # default threshold
        end
        qmap = romeovoxelquality(phase; keyargs...)
        keyargs[:mask] = mask_from_voxelquality(qmap, threshold)
        savenii(keyargs[:mask], "mask", writedir, hdr)
    end

    ## Perform unwrapping
    settings["verbose"] && println("perform unwrapping...")
    regions=zeros(UInt8, size(phase)[1:3]) # regions is an output
    unwrap!(phase; keyargs..., regions)
    settings["verbose"] && println("unwrapping finished!")

    if settings["max-seeds"] > 1
        settings["verbose"] && println("writing regions...")
        savenii(regions, "regions", writedir, hdr)
    end

    if settings["threshold"] != Inf
        max = settings["threshold"] * 2π
        phase[phase .> max] .= 0
        phase[phase .< -max] .= 0
    end

    if settings["mask-unwrapped"] && haskey(keyargs, :mask)
        phase .*= keyargs[:mask]
    end

    savenii(phase, filename, writedir, hdr)

    if settings["compute-B0"]
        if isempty(settings["echo-times"])
            error("echo times are required for B0 calculation! Unwrapping has been performed")
        end
        if !haskey(keyargs, :mag)
            if length(keyargs[:TEs]) > 1
                @warn "B0 frequency estimation without magnitude might result in poor handling of noise in later echoes!"
            end
            keyargs[:mag] = to_dim(exp.(-keyargs[:TEs]/20), 4) # T2*=20ms decay (low value to reduce noise problems in later echoes)
        end
        B0 = calculateB0_unwrapped(phase, keyargs[:mag], keyargs[:TEs])
        savenii(B0, "B0", writedir, hdr)
    end

    # no mask used for writing quality maps
    if settings["write-quality"]
        settings["verbose"] && println("Calculate and write quality map...")
        savenii(romeovoxelquality(phase; keyargs...), "quality", writedir, hdr)
    end
    if settings["write-quality-all"]
        for i in 1:4
            flags = falses(4)
            flags[i] = true
            settings["verbose"] && println("Calculate and write quality map $i...")
            voxelquality = romeovoxelquality(phase; keyargs..., weights=flags)
            if all(voxelquality[1:end-1,1:end-1,1:end-1] .== 1.0)
                settings["verbose"] && println("quality map $i skipped for the given inputs")
            else
                savenii(voxelquality, "quality_$i", writedir, hdr)
            end
        end
    end

    return 0
end
