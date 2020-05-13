function readphase(fn; keyargs...)
    phase = niread(fn; keyargs...)
    minp, maxp = approxextrema(phase)
    phase.header.scl_slope = 2pi / (maxp - minp)
    phase.header.scl_inter = -pi - minp * phase.header.scl_slope
    return phase
end

function readmag(fn; normalize=false, keyargs...)
    mag = niread(fn; keyargs...)
    if mag.header.scl_slope == 0 || normalize
        _, maxi = approxextrema(mag)
        mag.header.scl_slope = 1 / maxi
        mag.header.scl_inter = 0
    end
    return mag
end

Base.copy(x::NIfTI.NIfTI1Header) = NIfTI.NIfTI1Header([getfield(x, k) for k ∈ fieldnames(NIfTI.NIfTI1Header)]...)

function Base.similar(header::NIfTI.NIfTI1Header)
    hdr = copy(header)
    hdr.scl_inter = 0
    hdr.scl_slope = 1
    return hdr
end

header(v::NIfTI.NIVolume) = similar(v.header)

approxextrema(I::NIVolume) = approxextrema(I.raw)
function approxextrema(I)
    startindices = round.(Int, range(firstindex(I), lastindex(I); length=100))
    indices = vcat((i .+ (1:100) for i in startindices)...)
    indices = filter(ind -> checkbounds(Bool, I, ind), indices)
    samples = filter(isfinite, I[indices])
    return minimum(samples), maximum(samples)
end

savenii(image, name, writedir::Nothing, header=nothing) = nothing
function savenii(image, name, writedir::String, header=nothing)
    if splitext(name)[2] != ".nii"
        name = name * ".nii"
    end
    savenii(image, joinpath(writedir, name); header=header)
end
"""
    savenii(image, filepath; header=nothing)
save the image at the path
Warning: MRIcro can only open images with types Int32, Int64, Float32, Float64
"""
function savenii(image::AbstractArray, filepath::AbstractString; header=nothing)
    vol = NIVolume([h for h in [header] if h != nothing]..., Float32.(image))
    niwrite(filepath, vol)
end

function estimatenoise(weight)
    # find corner with lowest intensity
    d = size(weight)
    n = min.(10, d .÷ 3) # take 10 voxel but maximum a third
    getrange(num, len) = [1:len, (len-num+1):len] # first and last voxels
    corners = Iterators.product(getrange.(n, d)...)
    lowestmean = Inf
    sigma = 0
    for I in corners
        m = mean(filter(isfinite, weight[I...]))
        if m < lowestmean
            lowestmean = m
            sigma = std(filter(isfinite, weight[I...]))
        end
    end
    return lowestmean, sigma
end

function robustmask!(image; maskedvalue=if eltype(image) <: AbstractFloat NaN else 0 end)
    image[.!robustmask(image)] .= maskedvalue
    image
end
function robustmask(weight)
    μ, σ = estimatenoise(weight)
    return weight .> μ + 3σ
end
