extends GutTest

## Tests for InputCodec — 4-byte input serialization round-trips.

const CodecScript := preload("res://carom/scripts/netcode/input_codec.gd")

var Codec: GDScript


func before_all() -> void:
	Codec = CodecScript


func test_round_trip_basic() -> void:
	var aim: float = 1.5
	var fire: bool = true
	var reload: bool = false
	var frame: int = 42

	var encoded: PackedByteArray = Codec.encode(aim, fire, reload, frame)
	assert_eq(encoded.size(), 4, "Encoded packet should be 4 bytes")

	var decoded: Dictionary = Codec.decode(encoded)
	assert_eq(decoded.frame, 42)
	assert_eq(decoded.fire, true)
	assert_eq(decoded.reload, false)
	# Aim angle should be close (within quantization error)
	var aim_back: float = float(decoded.aim) / float(Codec.FP_TWO_PI) * TAU
	assert_almost_eq(aim_back, aim, 0.007, "Aim round-trip error should be < 0.007 rad")


func test_round_trip_all_flags() -> void:
	var encoded: PackedByteArray = Codec.encode(3.0, true, true, 1000)
	var decoded: Dictionary = Codec.decode(encoded)
	assert_eq(decoded.fire, true)
	assert_eq(decoded.reload, true)
	assert_eq(decoded.frame, 1000)


func test_round_trip_no_flags() -> void:
	var encoded: PackedByteArray = Codec.encode(0.0, false, false, 0)
	var decoded: Dictionary = Codec.decode(encoded)
	assert_eq(decoded.fire, false)
	assert_eq(decoded.reload, false)
	assert_eq(decoded.frame, 0)
	assert_eq(decoded.aim, 0)


func test_quantization_accuracy() -> void:
	# Test multiple angles — all should round-trip with < 0.007 rad error
	var test_angles: Array[float] = [0.0, 0.5, 1.0, PI, TAU - 0.01, TAU / 4.0, TAU * 3.0 / 4.0]
	for angle in test_angles:
		var encoded: PackedByteArray = Codec.encode(angle, false, false, 0)
		var decoded: Dictionary = Codec.decode(encoded)
		var aim_back: float = float(decoded.aim) / float(Codec.FP_TWO_PI) * TAU
		var err: float = absf(aim_back - fmod(angle, TAU))
		assert_lt(err, 0.007, "Angle %f quantization error %f should be < 0.007" % [angle, err])


func test_frame_wrapping() -> void:
	# Frame 65535 should encode/decode correctly
	var encoded: PackedByteArray = Codec.encode(0.0, false, false, 65535)
	var decoded: Dictionary = Codec.decode(encoded)
	assert_eq(decoded.frame, 65535)

	# Frame 65536 wraps to 0
	encoded = Codec.encode(0.0, false, false, 65536)
	decoded = Codec.decode(encoded)
	assert_eq(decoded.frame, 0, "Frame 65536 should wrap to 0")

	# Frame 65537 wraps to 1
	encoded = Codec.encode(0.0, false, false, 65537)
	decoded = Codec.decode(encoded)
	assert_eq(decoded.frame, 1, "Frame 65537 should wrap to 1")


func test_negative_angle_normalized() -> void:
	var encoded: PackedByteArray = Codec.encode(-1.0, false, false, 0)
	var decoded: Dictionary = Codec.decode(encoded)
	# Negative angle should be normalized to [0, 2π)
	assert_gt(decoded.aim, 0, "Negative angle should normalize to positive FP value")


func test_pack_unpack_input() -> void:
	var aim_fp: int = 100000
	var fire: bool = true
	var reload: bool = true
	var packed: int = Codec.pack_input(aim_fp, fire, reload)
	var unpacked: Dictionary = Codec.unpack_input(packed)
	# aim is truncated to 16 bits in packed format
	assert_eq(unpacked.aim, aim_fp & 0xFFFF)
	assert_eq(unpacked.fire, true)
	assert_eq(unpacked.reload, true)


func test_decode_empty_returns_empty() -> void:
	var empty := PackedByteArray()
	var decoded: Dictionary = Codec.decode(empty)
	assert_eq(decoded.size(), 0, "Decoding empty data should return empty dict")


func test_all_bits_independent() -> void:
	# Ensure fire and reload bits don't interfere with each other or aim
	var e1: PackedByteArray = Codec.encode(PI, true, false, 500)
	var e2: PackedByteArray = Codec.encode(PI, false, true, 500)
	var e3: PackedByteArray = Codec.encode(PI, true, true, 500)
	var d1: Dictionary = Codec.decode(e1)
	var d2: Dictionary = Codec.decode(e2)
	var d3: Dictionary = Codec.decode(e3)
	assert_eq(d1.fire, true); assert_eq(d1.reload, false)
	assert_eq(d2.fire, false); assert_eq(d2.reload, true)
	assert_eq(d3.fire, true); assert_eq(d3.reload, true)
	# All three should have the same aim value
	assert_eq(d1.aim, d2.aim)
	assert_eq(d2.aim, d3.aim)
