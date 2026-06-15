class_name FP
extends RefCounted

## Fixed-point arithmetic library — 48.16 format.
## All values are plain ints; lower 16 bits are the fractional part.
## No float arithmetic is used in any computation path — floats only appear
## in from_float() and to_float() which are for initialisation / rendering only.

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const SHIFT: int = 16
const ONE: int   = 1 << SHIFT    # 65536
const HALF: int  = 1 << 15       # 32768
const ZERO: int  = 0

# ---------------------------------------------------------------------------
# Conversions
# ---------------------------------------------------------------------------

## Convert an integer to fixed-point.
static func from_int(n: int) -> int:
	return n << SHIFT

## Convert a float to fixed-point (initialisation only — never in sim loop).
static func from_float(f: float) -> int:
	return int(f * ONE)

## Convert a fixed-point value to float (rendering only).
static func to_float(fp: int) -> float:
	return float(fp) / float(ONE)

# ---------------------------------------------------------------------------
# Arithmetic
# ---------------------------------------------------------------------------

## Fixed-point multiply: (a * b) >> SHIFT.
static func mul(a: int, b: int) -> int:
	return (a * b) >> SHIFT

## Fixed-point divide: (a << SHIFT) / b.
static func div(a: int, b: int) -> int:
	return (a << SHIFT) / b

## Integer square root using the digit-by-digit method (no floating point).
## Input is a fixed-point value; result is also fixed-point.
## Computes floor(sqrt(a * ONE)) so the result is in 48.16 form.
static func sqrt(a: int) -> int:
	if a <= 0:
		return 0
	# We want sqrt of the 48.16 value, which equals floor(sqrt(a << SHIFT)).
	# Scale up by SHIFT so the integer sqrt gives us a fixed-point result.
	var n: int = a << SHIFT
	if n < 0:
		# Overflow guard for very large values — fall back gracefully.
		n = 0x7FFFFFFFFFFFFFFF
	var x: int = n
	var result: int = 0
	var bit: int = 1 << 62  # Highest power-of-four ≤ 2^62
	while bit > x:
		bit >>= 2
	while bit > 0:
		if x >= result + bit:
			x -= result + bit
			result = (result >> 1) + bit
		else:
			result >>= 1
		bit >>= 2
	return result

## Absolute value of a fixed-point number.
static func abs_fp(a: int) -> int:
	return -a if a < 0 else a

## Sign of a fixed-point number.  Returns FP +1 or FP -1.
## Zero is treated as positive and returns ONE.
static func sign_fp(a: int) -> int:
	return -ONE if a < 0 else ONE

## Linear interpolation between a and b; t is a fixed-point value in [0, ONE].
## lerp_fp(a, b, 0) == a, lerp_fp(a, b, ONE) == b.
static func lerp_fp(a: int, b: int, t: int) -> int:
	return a + mul(b - a, t)

# ---------------------------------------------------------------------------
# FPVec2 — lightweight 2-D fixed-point vector (dictionary with x, y ints)
# ---------------------------------------------------------------------------

class FPVec2:
	## Create a new FPVec2 dictionary.
	static func make(x: int, y: int) -> Dictionary:
		return {x = x, y = y}

	## Component-wise addition.
	static func add(a: Dictionary, b: Dictionary) -> Dictionary:
		return {x = a.x + b.x, y = a.y + b.y}

	## Component-wise subtraction.
	static func sub(a: Dictionary, b: Dictionary) -> Dictionary:
		return {x = a.x - b.x, y = a.y - b.y}

	## Scale a vector by a fixed-point scalar.
	static func scale(v: Dictionary, scalar: int) -> Dictionary:
		return {x = FP.mul(v.x, scalar), y = FP.mul(v.y, scalar)}

	## Fixed-point dot product.
	static func dot(a: Dictionary, b: Dictionary) -> int:
		return FP.mul(a.x, b.x) + FP.mul(a.y, b.y)

	## Squared length (stays in fixed-point; no sqrt needed for comparisons).
	static func length_squared(v: Dictionary) -> int:
		return dot(v, v)

	## Length of the vector (fixed-point result).
	static func length(v: Dictionary) -> int:
		return FP.sqrt(length_squared(v))

	## Normalise a vector to unit length.  Returns the zero vector if length is 0.
	static func normalize(v: Dictionary) -> Dictionary:
		var len: int = length(v)
		if len == 0:
			return {x = 0, y = 0}
		return {x = FP.div(v.x, len), y = FP.div(v.y, len)}

	## Squared distance between two points.
	static func distance_squared(a: Dictionary, b: Dictionary) -> int:
		return length_squared(sub(a, b))

	## Distance between two points (fixed-point result).
	static func distance(a: Dictionary, b: Dictionary) -> int:
		return FP.sqrt(distance_squared(a, b))
