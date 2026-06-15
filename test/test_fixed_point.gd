extends GutTest

## Unit tests for FP (fixed-point 48.16 math library) and FP.FPVec2.
## All computation must use only integer arithmetic — floats appear only in
## from_float / to_float, which are tested here for round-trip accuracy.
##
## FPScript holds the preloaded script for scalar helpers (from_int, mul, …).
## FP.FPVec2 is accessed via the global class_name declared in fixed_point.gd —
## both aliases resolve to the same class at runtime.

const FPScript := preload("res://carom/scripts/sim/fixed_point.gd")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _fp(n: int) -> int:
	return FPScript.from_int(n)

func _fpf(f: float) -> int:
	return FPScript.from_float(f)

func _tof(fp: int) -> float:
	return FPScript.to_float(fp)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

func test_one_equals_65536() -> void:
	assert_eq(FPScript.ONE, 65536)

func test_half_equals_32768() -> void:
	assert_eq(FPScript.HALF, 32768)

func test_zero_equals_0() -> void:
	assert_eq(FPScript.ZERO, 0)

# ---------------------------------------------------------------------------
# Conversions
# ---------------------------------------------------------------------------

func test_from_int_positive() -> void:
	assert_eq(_fp(1), FPScript.ONE)
	assert_eq(_fp(5), 5 * FPScript.ONE)

func test_from_int_zero() -> void:
	assert_eq(_fp(0), 0)

func test_from_int_negative() -> void:
	assert_eq(_fp(-3), -3 * FPScript.ONE)

func test_round_trip_accuracy_positive() -> void:
	for i in range(101):
		var f := float(i)
		var err := absf(_tof(_fpf(f)) - f)
		assert_lt(err, 0.0001, "round-trip error too large for %.1f: %.6f" % [f, err])

func test_round_trip_accuracy_negative() -> void:
	for i in range(1, 101):
		var f := -float(i)
		var err := absf(_tof(_fpf(f)) - f)
		assert_lt(err, 0.0001, "round-trip error too large for %.1f: %.6f" % [f, err])

func test_round_trip_fractional() -> void:
	var cases: Array[float] = [0.5, 0.25, 0.1, 3.14159, -2.718, 99.999]
	for f in cases:
		var err := absf(_tof(_fpf(f)) - f)
		assert_lt(err, 0.0001, "round-trip error too large for %f: %.6f" % [f, err])

# ---------------------------------------------------------------------------
# Multiply
# ---------------------------------------------------------------------------

func test_mul_integers() -> void:
	assert_eq(FPScript.mul(_fp(3), _fp(4)), _fp(12))

func test_mul_by_zero() -> void:
	assert_eq(FPScript.mul(_fp(100), FPScript.ZERO), 0)

func test_mul_by_one() -> void:
	assert_eq(FPScript.mul(_fp(7), FPScript.ONE), _fp(7))

func test_mul_negative() -> void:
	assert_eq(FPScript.mul(_fp(-3), _fp(4)), _fp(-12))

func test_mul_both_negative() -> void:
	assert_eq(FPScript.mul(_fp(-3), _fp(-4)), _fp(12))

func test_mul_fractional() -> void:
	# 2.5 * 4.0 = 10.0
	var a: int = _fpf(2.5)
	var b: int = _fp(4)
	var err := absf(_tof(FPScript.mul(a, b)) - 10.0)
	assert_lt(err, 0.0001, "2.5 * 4 round-trip error: %f" % err)

# ---------------------------------------------------------------------------
# Divide
# ---------------------------------------------------------------------------

func test_div_exact() -> void:
	assert_eq(FPScript.div(_fp(12), _fp(4)), _fp(3))

func test_div_with_remainder() -> void:
	# 10 / 3 ≈ 3.3333
	var result: float = _tof(FPScript.div(_fp(10), _fp(3)))
	assert_almost_eq(result, 10.0 / 3.0, 0.001)

func test_div_by_one() -> void:
	assert_eq(FPScript.div(_fp(42), FPScript.ONE), _fp(42))

func test_div_negative() -> void:
	var result: float = _tof(FPScript.div(_fp(-10), _fp(2)))
	assert_almost_eq(result, -5.0, 0.0001)

# ---------------------------------------------------------------------------
# sqrt
# ---------------------------------------------------------------------------

func test_sqrt_perfect_square() -> void:
	assert_eq(FPScript.sqrt(_fp(25)), _fp(5))

func test_sqrt_four() -> void:
	assert_eq(FPScript.sqrt(_fp(4)), _fp(2))

func test_sqrt_one() -> void:
	assert_eq(FPScript.sqrt(_fp(1)), _fp(1))

func test_sqrt_zero() -> void:
	assert_eq(FPScript.sqrt(0), 0)

func test_sqrt_two_approx() -> void:
	# sqrt(2) ≈ 1.41421
	var result: float = _tof(FPScript.sqrt(_fp(2)))
	assert_almost_eq(result, 1.41421, 0.001)

func test_sqrt_large() -> void:
	# sqrt(10000) = 100
	var result: float = _tof(FPScript.sqrt(_fp(10000)))
	assert_almost_eq(result, 100.0, 0.01)

# ---------------------------------------------------------------------------
# abs_fp
# ---------------------------------------------------------------------------

func test_abs_positive() -> void:
	assert_eq(FPScript.abs_fp(_fp(5)), _fp(5))

func test_abs_negative() -> void:
	assert_eq(FPScript.abs_fp(_fp(-5)), _fp(5))

func test_abs_zero() -> void:
	assert_eq(FPScript.abs_fp(0), 0)

# ---------------------------------------------------------------------------
# sign_fp
# ---------------------------------------------------------------------------

func test_sign_positive() -> void:
	assert_eq(FPScript.sign_fp(_fp(3)), FPScript.ONE)

func test_sign_negative() -> void:
	assert_eq(FPScript.sign_fp(_fp(-3)), -FPScript.ONE)

func test_sign_negative_fractional() -> void:
	assert_eq(FPScript.sign_fp(-1), -FPScript.ONE)

# ---------------------------------------------------------------------------
# lerp_fp
# ---------------------------------------------------------------------------

func test_lerp_at_zero() -> void:
	assert_eq(FPScript.lerp_fp(_fp(2), _fp(10), 0), _fp(2))

func test_lerp_at_one() -> void:
	assert_eq(FPScript.lerp_fp(_fp(2), _fp(10), FPScript.ONE), _fp(10))

func test_lerp_at_half() -> void:
	var result: float = _tof(FPScript.lerp_fp(_fp(2), _fp(10), FPScript.HALF))
	assert_almost_eq(result, 6.0, 0.001)

# ---------------------------------------------------------------------------
# FPVec2 — basic operations
# ---------------------------------------------------------------------------

func test_vec2_add() -> void:
	var a := FP.FPVec2.make(_fp(1), _fp(2))
	var b := FP.FPVec2.make(_fp(3), _fp(4))
	var c: Dictionary = FP.FPVec2.add(a, b)
	assert_eq(c.x, _fp(4))
	assert_eq(c.y, _fp(6))

func test_vec2_sub() -> void:
	var a := FP.FPVec2.make(_fp(5), _fp(3))
	var b := FP.FPVec2.make(_fp(2), _fp(1))
	var c: Dictionary = FP.FPVec2.sub(a, b)
	assert_eq(c.x, _fp(3))
	assert_eq(c.y, _fp(2))

func test_vec2_scale() -> void:
	var v := FP.FPVec2.make(_fp(3), _fp(4))
	var s: Dictionary = FP.FPVec2.scale(v, _fp(2))
	assert_eq(s.x, _fp(6))
	assert_eq(s.y, _fp(8))

func test_vec2_dot() -> void:
	var a := FP.FPVec2.make(_fp(3), _fp(4))
	var b := FP.FPVec2.make(_fp(1), _fp(2))
	# 3*1 + 4*2 = 11
	assert_eq(FP.FPVec2.dot(a, b), _fp(11))

func test_vec2_length_squared() -> void:
	var v := FP.FPVec2.make(_fp(3), _fp(4))
	# 3^2 + 4^2 = 25
	assert_eq(FP.FPVec2.length_squared(v), _fp(25))

func test_vec2_length_3_4() -> void:
	var v := FP.FPVec2.make(_fp(3), _fp(4))
	# length = 5
	assert_eq(FP.FPVec2.length(v), _fp(5))

func test_vec2_normalize_unit_length() -> void:
	var v := FP.FPVec2.make(_fp(3), _fp(4))
	var n: Dictionary = FP.FPVec2.normalize(v)
	var len: int = FP.FPVec2.length(n)
	# Should be ONE ± 2 LSB (inherent rounding from two integer divisions)
	assert_true(absf(float(len - FPScript.ONE)) <= 2.0,
		"normalize length should be ONE ±2 LSB, got %d (ONE=%d)" % [len, FPScript.ONE])

func test_vec2_normalize_axis_aligned() -> void:
	var v := FP.FPVec2.make(_fp(5), 0)
	var n: Dictionary = FP.FPVec2.normalize(v)
	assert_eq(n.x, FPScript.ONE)
	assert_eq(n.y, 0)

func test_vec2_normalize_zero_vector() -> void:
	var v := FP.FPVec2.make(0, 0)
	var n: Dictionary = FP.FPVec2.normalize(v)
	assert_eq(n.x, 0)
	assert_eq(n.y, 0)

func test_vec2_distance_squared() -> void:
	var a := FP.FPVec2.make(_fp(0), _fp(0))
	var b := FP.FPVec2.make(_fp(3), _fp(4))
	assert_eq(FP.FPVec2.distance_squared(a, b), _fp(25))

func test_vec2_distance() -> void:
	var a := FP.FPVec2.make(_fp(0), _fp(0))
	var b := FP.FPVec2.make(_fp(3), _fp(4))
	assert_eq(FP.FPVec2.distance(a, b), _fp(5))

# ---------------------------------------------------------------------------
# Overflow edge cases
# ---------------------------------------------------------------------------

func test_large_value_mul_does_not_crash() -> void:
	# Use values near int32 limit in fixed-point representation.
	# These are valid int64 operations in GDScript.
	var a: int = _fp(1000)
	var b: int = _fp(1000)
	var result: int = FPScript.mul(a, b)
	assert_almost_eq(_tof(result), 1000000.0, 1.0)

func test_sqrt_large_no_crash() -> void:
	var result: int = FPScript.sqrt(_fp(1000000))
	assert_almost_eq(_tof(result), 1000.0, 0.5)

func test_abs_large_negative() -> void:
	var a: int = _fp(-50000)
	assert_eq(FPScript.abs_fp(a), _fp(50000))
