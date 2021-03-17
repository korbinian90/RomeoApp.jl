function unwrapping_main(args)
    settings = getargs(args)

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

    if settings["mask-unwrapped"] && settings["mask"] == "nomask"
        settings["mask"] = "robustmask"
    end

    mkpath(writedir)
    saveconfiguration(writedir, settings, args)

    phasenii = readphase(settings["phase"], mmap=!settings["no-mmap"], rescale=!settings["no-rescale"])
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
    settings["verbose"] && println("Echoes are $echoes")

    phase = phasenii[:,:,:,echoes]
    phasenii = nothing
    settings["verbose"] && println("Phase loaded!")

    keyargs = Dict()
    if !isnothing(settings["magnitude"])
        keyargs[:mag] = view(readmag(settings["magnitude"], mmap=!settings["no-mmap"]),:,:,:,echoes)
        if size(keyargs[:mag]) != size(phase)
            error("size of magnitude and phase does not match!")
        end
        settings["verbose"] && println("Magnitude loaded!")
    end

    keyargs[:correctglobal] = settings["correct-global"]
    keyargs[:weights] = parseweights(settings)
    if length(echoes) > 1
        keyargs[:TEs] = getTEs(settings, neco, echoes)
        settings["verbose"] && println("TEs are $(keyargs[:TEs])")
    end

    ## Error messages
    if 1 < length(echoes) && length(echoes) != length(keyargs[:TEs])
        error("Number of chosen echoes is $(length(echoes)) ($neco in .nii data), but $(length(keyargs[:TEs])) TEs were specified!")
    end

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
    settings["verbose"] && println("echo $(keyargs[:template]) used as template")

    # no mask defined for writing quality maps
    if settings["write-quality"]
        settings["verbose"] && println("Calculate and write quality map...")
        weights = ROMEO.calculateweights(phase; type=Float32, rescale=x->x, keyargs...)
        savenii(getvoxelquality(weights), "quality", writedir, hdr)
    end
    if settings["write-quality-all"]
        for i in 1:4
            flags = falses(4)
            flags[i] = true
            settings["verbose"] && println("Calculate and write quality map $i...")
            weights = ROMEO.calculateweights(phase; type=Float32, rescale=x->x, keyargs..., weights=flags)
            if all(weights[:,1:end-1,1:end-1,1:end-1] .== 1.0)
                settings["verbose"] && println("quality map $i skipped for the given inputs")
            else
                savenii(getvoxelquality(weights), "quality_$i", writedir, hdr)
            end
        end
    end

    ## set mask
    if isfile(settings["mask"])
        settings["verbose"] && println("Trying to read mask from file $(settings["mask"])")
        keyargs[:mask] = niread(settings["mask"]) .!= 0
        if size(keyargs[:mask]) != size(phase)[1:3]
            error("size of mask is $(size(keyargs[:mask])), but it should be $(size(phase)[1:3])!")
        end
    elseif settings["mask"] == "robustmask" && haskey(keyargs, :mag)
        settings["verbose"] && println("Calculate robustmask from magnitude, saved as mask.nii")
        mag = keyargs[:mag]
        template_echo = min(keyargs[:template], size(mag, 4))
        keyargs[:mask] = robustmask(mag[:,:,:,template_echo])
        savenii(keyargs[:mask], "mask", writedir, hdr)
    end

    ## Perform phase offset correction
    if settings["phase-offset-correction"]
        settings["verbose"] && println("perform phase offset correction with MCPC3D-S...")
        if all(keyargs[:TEs] .== 1)
            error("Phase offset determination requires the echo times!")
        end
        po = zeros(Complex{eltype(phase)}, (size(phase)[1:3]...,1))
        mag = if haskey(keyargs, :mag) keyargs[:mag] else ones(size(phase)) end
        phase, _ = mcpc3ds(phase, mag; TEs=keyargs[:TEs], po=po)
        savenii(phase, "corrected_phase", writedir, hdr)
        savenii(angle.(po), "phase_offset", writedir, hdr)
    end

    ## Perform unwrapping
    settings["verbose"] && println("perform unwrapping...")
    regions=zeros(UInt8, size(phase)[1:3])
    unwrap!(phase; regions=regions, keyargs...)
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
        phase[.!keyargs[:mask]] .= 0
    end

    savenii(phase, filename, writedir, hdr)

    if settings["compute-B0"]
        if isnothing(settings["echo-times"])
            error("echo times are required for B0 calculation! Unwrapping has been performed")
        end
        if !haskey(keyargs, :mag)
            @warn "B0 frequency estimation without magnitude might result in poor handling of noise in later echoes!"        
            keyargs[:mag] = to_dim(exp.(-keyargs[:TEs]/20), 4) # T2*=20ms decay (low value to reduce noise problems in later echoes)
        end
        B0 = MriResearchTools.calculateB0_unwrapped(phase, keyargs[:mag], keyargs[:TEs])
        savenii(B0, "B0", writedir, hdr)
    end

    return 0
end

function ROMEO.calculateweights(phase::AbstractArray{T,4}; TEs, template=2, p2ref=1, keyargs...) where T
    args = Dict{Symbol, Any}(keyargs)
    args[:phase2] = phase[:,:,:,p2ref]
    args[:TEs] = TEs[[template, p2ref]]
    if haskey(args, :mag)
        args[:mag] = args[:mag][:,:,:,template]
    end
    return ROMEO.calculateweights(view(phase,:,:,:,template); args...)
    
end

getvoxelquality(w::AbstractArray{<:AbstractFloat}) = dropdims(sum(w; dims=1); dims=1) ./ 3
