class_name SeededRng
extends RefCounted
## Deterministic, platform independent PRNG (xoshiro128**).
##
## Implemented with explicit 32-bit arithmetic so results never depend on the
## engine's RandomNumberGenerator implementation, the CPU, or the Godot
## version. The same seed always yields the same sequence.

const MASK32 := 0xFFFFFFFF

var _s0: int = 0
var _s1: int = 0
var _s2: int = 0
var _s3: int = 0


func _init(seed_value: int = 0) -> void:
	reseed(seed_value)


func reseed(seed_value: int) -> void:
	# Negative seeds are folded with ~ so only non-negative values are shifted.
	var v := seed_value if seed_value >= 0 else ~seed_value
	var lo := v & MASK32
	var hi := (v >> 32) & MASK32
	if seed_value < 0:
		hi ^= 0x5BD1E995
	var x := SeededRng.mix32(lo ^ SeededRng.mix32(hi ^ 0x9E3779B9))
	_s0 = SeededRng.mix32(x ^ 0x243F6A88)
	_s1 = SeededRng.mix32(_s0 ^ 0x85A308D3)
	_s2 = SeededRng.mix32(_s1 ^ 0x13198A2E)
	_s3 = SeededRng.mix32(_s2 ^ 0x03707344)
	if (_s0 | _s1 | _s2 | _s3) == 0:
		_s0 = 1


## Independent sub-stream derived from this generator's seed material and a
## salt; does not advance this generator.
func fork(salt: int) -> SeededRng:
	var r := SeededRng.new()
	r._s0 = SeededRng.mix32(_s0 ^ SeededRng.mix32(salt & MASK32))
	r._s1 = SeededRng.mix32(_s1 ^ 0x6A09E667 ^ salt)
	r._s2 = SeededRng.mix32(_s2 ^ 0xBB67AE85)
	r._s3 = SeededRng.mix32(_s3 ^ 0x3C6EF372 ^ ((salt & MASK32) >> 7))
	if (r._s0 | r._s1 | r._s2 | r._s3) == 0:
		r._s0 = 1
	return r


func next_u32() -> int:
	var result := SeededRng.mul32(SeededRng.rotl(SeededRng.mul32(_s1, 5), 7), 9)
	var t := (_s1 << 9) & MASK32
	_s2 ^= _s0
	_s3 ^= _s1
	_s1 ^= _s2
	_s0 ^= _s3
	_s2 ^= t
	_s3 = SeededRng.rotl(_s3, 11)
	return result


## Uniform float in [0, 1).
func next_float() -> float:
	return next_u32() / 4294967296.0


## Uniform integer in [lo, hi] (inclusive).
func range_int(lo: int, hi: int) -> int:
	if hi <= lo:
		return lo
	return lo + int(next_float() * (hi - lo + 1))


func range_float(lo: float, hi: float) -> float:
	return lo + (hi - lo) * next_float()


func chance(p: float) -> bool:
	return next_float() < p


func pick(items: Array) -> Variant:
	if items.is_empty():
		return null
	return items[range_int(0, items.size() - 1)]


## Index chosen proportionally to non-negative weights.
func weighted_index(weights: Array) -> int:
	var total := 0.0
	for w in weights:
		total += maxf(0.0, float(w))
	if total <= 0.0:
		return 0
	var roll := next_float() * total
	for i in weights.size():
		roll -= maxf(0.0, float(weights[i]))
		if roll < 0.0:
			return i
	return weights.size() - 1


## In-place Fisher-Yates shuffle.
func shuffle(items: Array) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := range_int(0, i)
		var tmp: Variant = items[i]
		items[i] = items[j]
		items[j] = tmp


func shuffle_packed(items: PackedInt32Array) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := range_int(0, i)
		var tmp := items[i]
		items[i] = items[j]
		items[j] = tmp


# --- 32-bit helpers ---------------------------------------------------------

## (a * b) mod 2^32 without relying on 64-bit overflow behaviour.
static func mul32(a: int, b: int) -> int:
	var al := a & 0xFFFF
	var ah := (a >> 16) & 0xFFFF
	var bl := b & 0xFFFF
	var bh := (b >> 16) & 0xFFFF
	return (al * bl + (((ah * bl + al * bh) & 0xFFFF) << 16)) & MASK32


static func rotl(x: int, k: int) -> int:
	return ((x << k) | (x >> (32 - k))) & MASK32


## Murmur3 finaliser: strong 32-bit avalanche.
static func mix32(value: int) -> int:
	var h := value & MASK32
	h ^= h >> 16
	h = mul32(h, 0x85EBCA6B)
	h ^= h >> 13
	h = mul32(h, 0xC2B2AE35)
	h ^= h >> 16
	return h


## Hash of a list of integers (each folded into 32 bits).
static func hash_ints(values: Array) -> int:
	var h := 0x811C9DC5
	for v in values:
		var x := int(v)
		var u := x if x >= 0 else ~x
		var lo := u & MASK32
		var hi := (u >> 32) & MASK32
		if x < 0:
			hi ^= 0xA5A5A5A5
		h = mix32(h ^ lo)
		h = mix32(h ^ hi ^ 0x27D4EB2F)
	return h


## Hash of a UTF-8 string (FNV-1a folded through mix32).
static func hash_string(text: String) -> int:
	var h := 0x811C9DC5
	for b in text.to_utf8_buffer():
		h = mul32(h ^ b, 0x01000193)
	return mix32(h)
