"""The Float32 + stochastic rounding type."""
primitive type Float32sr <: AbstractFloat 32 end

# basic properties
sign_mask(::Type{Float32sr}) = 0x8000_0000
exponent_mask(::Type{Float32sr}) = 0x7f80_0000
significand_mask(::Type{Float32sr}) = 0x007f_ffff
precision(::Type{Float32sr}) = 24

"""Mask for both sign and exponent bits. Equiv to ~significand_mask(Float64)."""
signexp_mask(::Type{Float64}) = 0xfff0_0000_0000_0000

one(::Type{Float32sr}) = reinterpret(Float32sr,one(Float32))
zero(::Type{Float32sr}) = reinterpret(Float32sr,0x0000_0000)
one(::Float32sr) = one(Float32sr)
zero(::Float32sr) = zero(Float32sr)

typemin(::Type{Float32sr}) = Float32sr(typemin(Float32))
typemax(::Type{Float32sr}) = Float32sr(typemax(Float32))
floatmin(::Type{Float32sr}) = Float32sr(floatmin(Float32))
floatmax(::Type{Float32sr}) = Float32sr(floatmax(Float32))

typemin(::Float32sr) = typemin(Float32sr)
typemax(::Float32sr) = typemax(Float32sr)
floatmin(::Float32sr) = floatmin(Float32sr)
floatmax(::Float32sr) = floatmax(Float32sr)

eps(::Type{Float32sr}) = Float32sr(eps(Float32))
eps(x::Float32sr) = Float32sr(eps(Float32(x)))

const Inf32sr = reinterpret(Float32sr, Inf32)
const NaN32sr = reinterpret(Float32sr, NaN32)

# basic operations
abs(x::Float32sr) = reinterpret(Float32sr, abs(reinterpret(Float32)))
isnan(x::Float32sr) = isnan(reinterpret(Float32,x))
isfinite(x::Float32sr) = isfinite(reinterpret(Float32,x))

nextfloat(x::Float32sr) = Float32sr(nextfloat(Float32(x)))
prevfloat(x::Float32sr) = Float32sr(prevfloat(Float32(x)))

-(x::Float32sr) = reinterpret(Float32sr, reinterpret(UInt32, x) ⊻ sign_mask(Float32sr))

# conversions
Float32(x::Float32sr) = reinterpret(Float32,x)
Float32sr(x::Float32) = reinterpret(Float32sr,x)
Float32sr(x::Float16) = Float32sr(Float32(x))
Float32sr(x::Float64) = Float32sr(Float32(x))
Float16(x::Float32sr) = Float16(Float32(x))
Float64(x::Float32sr) = Float64(Float32(x))

Float32sr(x::Integer) = Float32sr(Float32(x))
(::Type{T})(x::Float32sr) where {T<:Integer} = T(Float32(x))

"""Convert to Float32sr from Float64 with stochastic rounding.
Binary arithmetic version."""
function Float32_stochastic_round(x::Float64)
	# check whether round to nearest maps to zero(Float32)
	# to avoid stochastic rounding to NaN
	iszero(Float32(x)) && return zero(Float32sr)

	# r are random bits for the last 31
	# >> either introduces 0s for the first 33 bits
	# or 1s. Interpreted as Int64 this corresponds to [-ulp/2,ulp/2)
	# which is added with binary arithmetic subsequently
	# this is the stochastic perturbation.
	# Then deterministic round to nearest to either round up or round down.
	r = rand(Xor128[],Int64) >> 35   # = 32sbits+3expbits difference between f32,f64
	xr = reinterpret(Float64,reinterpret(Int64,x) + r)
	return Float32sr(xr)			# round to nearest
end

const F64_one = reinterpret(UInt64,one(Float64))

"""Chance that x::Float64 is round up when converted to Float32sr."""
function Float32_chance_roundup(x::Float64)
	isnan(x) && return NaN32sr
	ui = reinterpret(UInt64, x)
	# sig is the signficand (exponents & sign is masked out)
	sig = ui & significand_mask(Float64)
	frac = reinterpret(Float64,F64_one | (sig << 23)) - 1.0
	# sig << 23, push significant bits that would be round away into the most
	# most significant bits, then set the exponent to be equi to one(Float64)
	# as there are more significant bits than exponent bits make sure that
	# the sign and the first exponent bit is zero by applying the 0x3fff mask
	frac = reinterpret(Float64,0x3fff_ffff_ffff_ffff & (F64_one | (sig << 23))) - 1.0
	return frac
end

# Promotion
promote_rule(::Type{Float16}, ::Type{Float32sr}) = Float32
promote_rule(::Type{Float64}, ::Type{Float32sr}) = Float64

for t in (Int8, Int16, Int32, Int64, Int128, UInt8, UInt16, UInt32, UInt64, UInt128)
    @eval promote_rule(::Type{Float32sr}, ::Type{$t}) = Float32sr
end

# Rounding
round(x::Float32sr, r::RoundingMode{:ToZero}) = Float32sr(round(Float32(x), r))
round(x::Float32sr, r::RoundingMode{:Down}) = Float32sr(round(Float32(x), r))
round(x::Float32sr, r::RoundingMode{:Up}) = Float32sr(round(Float32(x), r))
round(x::Float32sr, r::RoundingMode{:Nearest}) = Float32sr(round(Float32(x), r))

# Comparison
function ==(x::Float32sr, y::Float32sr)
	return Float32(x) == Float32(y)
end

for op in (:<, :<=, :isless)
    @eval ($op)(a::Float32sr, b::Float32sr) = ($op)(Float32(a), Float32(b))
end

# Arithmetic
for f in (:+, :-, :*, :/, :^)
	@eval ($f)(x::Float32sr, y::Float32sr) = Float32_stochastic_round($(f)(Float64(x), Float64(y)))
end

for func in (:sin,:cos,:tan,:asin,:acos,:atan,:sinh,:cosh,:tanh,:asinh,:acosh,
             :atanh,:exp,:exp2,:exp10,:expm1,:log,:log2,:log10,:sqrt,:cbrt,:log1p)
    @eval begin
        Base.$func(a::Float32sr) = Float32_stochastic_round($func(Float64(a)))
    end
end

for func in (:atan,:hypot)
    @eval begin
        $func(a::Float32sr,b::Float32sr) = Float32_stochastic_round($func(Float64(a),Float64(b)))
    end
end


# Showing
function show(io::IO, x::Float32sr)
    if isinf(x)
        print(io, x < 0 ? "-Inf32sr" : "Inf32sr")
    elseif isnan(x)
        print(io, "NaN32sr")
    else
		io2 = IOBuffer()
        print(io2,Float32(x))
        f = String(take!(io2))
        print(io,"Float32sr("*f*")")
    end
end

bitstring(x::Float32sr) = bitstring(reinterpret(UInt32,x))

function bitstring(x::Float32sr,mode::Symbol)
    if mode == :split	# split into sign, exponent, signficand
        s = bitstring(x)
		return "$(s[1]) $(s[2:9]) $(s[10:end])"
    else
        return bitstring(x)
    end
end
