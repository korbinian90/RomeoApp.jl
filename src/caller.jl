function unwrapping_main(args)
    version = "3.4.0"

    settings = getargs(args, version)
    keyargs = Dict()
    
    writedir = settings["output"]
    filename = "unwrapped"
    if endswith(writedir, ".nii") || endswith(writedir, ".nii.gz")
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

    if settings["mask"][1] == "robustmask" && isnothing(settings["magnitude"])
        settings["mask"][1] = "nomask"
        @warn "robustmask was chosen but no magnitude is available. No mask is used!"
    end

    if last(splitext(settings["phase"])) == ".gz"
        settings["no-mmap"] = true
    end
    
    phase = readphase(settings["phase"], mmap=!settings["no-mmap"], rescale=!settings["no-rescale"])
    hdr = header(phase)
    neco = size(phase, 4)

    # activate phase-offset-correction as default (monopolar)
    multi_channel = size(phase, 5) > 1
    if (!isempty(settings["compute-B0"]) || multi_channel || settings["phase-offset-correction"] == "on") && settings["phase-offset-correction"] != "bipolar"
        settings["phase-offset-correction"] = "monopolar"
        settings["verbose"] && println("Phase offset correction with MCPC3D-S set to monopolar")
    end
    if neco == 1
        settings["phase-offset-correction"] = "off"
        settings["verbose"] && println("Phase offset correction with MCPC3D-S turned off (only one echo)")
    end

    mkpath(writedir)
    saveconfiguration(writedir, settings, args, version)

    ## Perform phase offset correction MCPC3D-S
    if settings["phase-offset-correction"] in ["monopolar", "bipolar"]
        polarity = settings["phase-offset-correction"]
        bipolar_correction = polarity == "bipolar"

        TEs = getTEs(settings, neco, :)
        if neco != length(TEs) error("Phase offset determination requires all echo times!") end
        if TEs[1] == TEs[2] error("The echo times need to be different for MCPC3D-S phase offset correction!") end
        
        settings["verbose"] && println("Perform phase offset correction with MCPC3D-S ($polarity)")
        settings["verbose"] && multi_channel && println("Perform coil combination with MCPC3D-S ($polarity)")

        po = zeros(eltype(phase), (size(phase)[1:3]...,size(phase,5)))
        mag = if !isnothing(settings["magnitude"]) readmag(settings["magnitude"], mmap=!settings["no-mmap"]) else ones(size(phase)) end # TODO trues instead ones?
        sigma_mm = get_phase_offset_smoothing_sigma(settings)
        sigma_vox = sigma_mm ./ header(phase).pixdim[2:4]
        phase, mcomb = mcpc3ds(phase, mag; TEs, po, bipolar_correction, σ=sigma_vox)
        
        if size(mag, 5) != 1
            keyargs[:mag] = mcomb
        end
        if multi_channel
            settings["verbose"] && println("Saving combined_phase, combined_mag and phase_offset")
            savenii(phase, "combined_phase", writedir, hdr)
            savenii(mcomb, "combined_mag", writedir, hdr)
        else
            settings["verbose"] && println("Saving corrected_phase and phase_offset")
            savenii(phase, "corrected_phase", writedir, hdr)
        end
        settings["write-phase-offsets"] && savenii(po, "phase_offset", writedir, hdr)
    end

    ## Echoes for unwrapping
    echoes = try
        getechoes(settings, neco)
    catch y
        if isa(y, BoundsError)
            error("echoes=$(join(settings["unwrap-echoes"], " ")): specified echo out of range! Number of echoes is $neco")
        else
            error("echoes=$(join(settings["unwrap-echoes"], " ")) wrongly formatted!")
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
        magnii = readmag(settings["magnitude"], mmap=!settings["no-mmap"])
        if size(magnii)[1:3] != size(phase)[1:3] || size(magnii, 4) < maximum(echoes)
            error("size of magnitude and phase does not match!")
        end
        keyargs[:mag] = view(magnii,:,:,:,echoes) # view avoids copy
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
        settings["verbose"] && println("Trying to read mask from file $(settings["mask"][1])")
        keyargs[:mask] = niread(settings["mask"][1]).raw .!= 0
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
            parse(Float32, settings["mask"][2])
        else
            0.1 # default threshold
        end
        qmap = romeovoxelquality(phase; keyargs...)
        keyargs[:mask] = robustmask(qmap; threshold)
        savenii(keyargs[:mask], "mask", writedir, hdr)
    elseif settings["mask"][1] != "nomask"
        opt = settings["mask"][1]
        error("masking option '$opt' is undefined" * ifelse(tryparse(Float32, opt) isa Float32, " (Maybe '-k qualitymask $opt' was meant?)", ""))
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

    if !isempty(settings["compute-B0"])
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
        savenii(B0, settings["compute-B0"], writedir, hdr)
    end

    # no mask used for writing quality maps
    if settings["write-quality"]
        settings["verbose"] && println("Calculate and write quality map...")
        savenii(romeovoxelquality(phase; keyargs...), "quality", writedir, hdr)
    end
    if settings["write-quality-all"]
        for i in 1:6
            flags = falses(6)
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
