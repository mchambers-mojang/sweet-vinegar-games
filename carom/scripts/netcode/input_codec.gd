class_name InputCodec
extends RefCounted

## 4-byte input packet encoder/decoder for Carom netcode.
##
## Bit layout (32 bits, big-endian):
##   [31..22] aim angle  — 10 bits (0–1023 → 0 to 2π)
##   [21]     fire       — 1 bit
##   [20]     reload     — 1 bit
##   [19..16] reserved   — 4 bits (zero)
##   [15..0]  frame      — 16 bits (wraps at 65535)

const AIM_BITS: int      = 10
const AIM_MAX: int       = (1 << AIM_BITS) - 1  # 1023
const FRAME_MASK: int    = 0xFFFF
const TWO_PI: float      = TAU  # 6.283185...

# Fixed-point 48.16 representation of 2π (must match SimWorld.FP_TWO_PI)
const FP_TWO_PI: int     = 411774


## Encode a local input into a 4-byte PackedByteArray.
## aim_angle_rad: turret aim in radians [0, 2π)
## fire: true if the player fired this tick
## reload: true if the player started reload this tick
## frame: tick number (wraps at 65535)
static func encode(aim_angle_rad: float, fire: bool, reload: bool, frame: int) -> PackedByteArray:
	# Quantize aim to 10 bits: [0, 2π) → [0, 1023]
	var aim_norm: float = fmod(aim_angle_rad, TWO_PI)
	if aim_norm < 0.0:
		aim_norm += TWO_PI
	var aim_q: int = clampi(roundi(aim_norm / TWO_PI * AIM_MAX), 0, AIM_MAX)

	var word: int = 0
	word |= (aim_q & AIM_MAX) << 22
	word |= (1 << 21) if fire else 0
	word |= (1 << 20) if reload else 0
	word |= frame & FRAME_MASK

	var buf := PackedByteArray()
	buf.resize(4)
	buf.encode_u32(0, word)
	return buf


## Decode a 4-byte packet into a Dictionary usable by RollbackManager.
## Returns: { frame: int, aim: int (FP angle), fire: bool, reload: bool }
static func decode(data: PackedByteArray) -> Dictionary:
	if data.size() < 4:
		return {}
	var word: int = data.decode_u32(0)

	var aim_q: int = (word >> 22) & AIM_MAX
	var fire: bool = ((word >> 21) & 1) == 1
	var reload: bool = ((word >> 20) & 1) == 1
	var frame: int = word & FRAME_MASK

	# Convert 10-bit quantized angle back to FP radians
	# aim_q / 1023 * FP_TWO_PI
	var aim_fp: int = aim_q * FP_TWO_PI / AIM_MAX

	return { frame = frame, aim = aim_fp, fire = fire, reload = reload }


## Pack decoded input fields into a single int for RollbackManager.
## Layout: [31..16] aim_fp(16 bits), [1] reload, [0] fire
## This is the format consumed by RollbackManager.advance_frame().
static func pack_input(aim_fp: int, fire: bool, reload: bool) -> int:
	var packed: int = 0
	packed |= (aim_fp & 0xFFFF) << 16
	packed |= (1 << 1) if reload else 0
	packed |= 1 if fire else 0
	return packed


## Unpack a RollbackManager input int back into components.
static func unpack_input(packed: int) -> Dictionary:
	return {
		aim = (packed >> 16) & 0xFFFF,
		fire = (packed & 1) == 1,
		reload = ((packed >> 1) & 1) == 1,
	}
