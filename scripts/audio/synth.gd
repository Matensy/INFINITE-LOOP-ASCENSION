class_name Synth
extends RefCounted
## Tiny offline synthesiser. All sounds and music loops are generated at
## runtime from code, so the APK ships no audio files at all.

const SFX_RATE := 22050
## Natural minor scale degrees (semitones) used for melodies.
const MINOR: Array[int] = [0, 2, 3, 5, 7, 8, 10]
## i - VI - III - VII progression as scale-degree roots.
const PROGRESSION: Array[int] = [0, 5, 2, 6]


static func midi_freq(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)


static func to_wav(samples: PackedFloat32Array, rate: int, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32000.0)
		if v < 0:
			v += 65536
		bytes[i * 2] = v & 0xFF
		bytes[i * 2 + 1] = (v >> 8) & 0xFF
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


static func buffer(seconds: float, rate: int = SFX_RATE) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * rate))
	return b


## Adds `src` into `dst` starting at `offset` seconds (wrapping when `wrap`).
static func mix(dst: PackedFloat32Array, src: PackedFloat32Array, offset: float, gain: float, rate: int = SFX_RATE, wrap: bool = false) -> void:
	var start := int(offset * rate)
	var n := dst.size()
	for i in src.size():
		var j := start + i
		if j >= n:
			if not wrap:
				break
			j %= n
		dst[j] += src[i] * gain


## Plucked tone: sine + octave partial, exponential decay, tiny pitch drop.
static func pluck(freq: float, seconds: float, brightness: float = 0.35, rate: int = SFX_RATE) -> PackedFloat32Array:
	var out := buffer(seconds, rate)
	var phase := 0.0
	var phase2 := 0.0
	var decay := 5.5 / seconds
	for i in out.size():
		var t := float(i) / rate
		var f := freq * (1.0 + 0.012 * exp(-t * 40.0))
		phase += f / rate
		phase2 += 2.0 * f / rate
		var env := exp(-t * decay) * minf(1.0, t * 400.0)
		out[i] = (sin(TAU * phase) + brightness * sin(TAU * phase2) * exp(-t * decay * 1.8)) * env
	return out


## FM bell: bright attack that mellows.
static func bell(freq: float, seconds: float, rate: int = SFX_RATE) -> PackedFloat32Array:
	var out := buffer(seconds, rate)
	var decay := 4.0 / seconds
	for i in out.size():
		var t := float(i) / rate
		var index := 2.2 * exp(-t * 6.0)
		var mod := sin(TAU * freq * 1.41 * t) * index
		var env := exp(-t * decay) * minf(1.0, t * 300.0)
		out[i] = sin(TAU * freq * t + mod) * env
	return out


## Filtered noise burst (clicks, whooshes).
static func noise(seconds: float, cutoff: float, attack: float, rng: SeededRng, rate: int = SFX_RATE) -> PackedFloat32Array:
	var out := buffer(seconds, rate)
	var a := clampf(cutoff / rate * TAU, 0.001, 1.0)
	var y := 0.0
	for i in out.size():
		var t := float(i) / rate
		var x := rng.next_float() * 2.0 - 1.0
		y += a * (x - y)
		var env := minf(1.0, t / maxf(attack, 0.0005)) * exp(-t * 6.0 / seconds)
		out[i] = y * env
	return out


## Low thud for refused actions.
static func thud(seconds: float, rate: int = SFX_RATE) -> PackedFloat32Array:
	var out := buffer(seconds, rate)
	var phase := 0.0
	for i in out.size():
		var t := float(i) / rate
		var f := lerpf(110.0, 55.0, t / seconds)
		phase += f / rate
		out[i] = sin(TAU * phase) * exp(-t * 18.0) * minf(1.0, t * 500.0)
	return out


static func normalize(buf: PackedFloat32Array, peak: float = 0.9) -> void:
	var m := 0.0001
	for v in buf:
		m = maxf(m, absf(v))
	var g := peak / m
	for i in buf.size():
		buf[i] *= g


## Sound-effect recipes tuned to a root note, as [name, Callable] pairs.
## Each Callable synthesises one AudioStreamWAV; AudioManager runs one per
## frame on the main thread so start-up never stalls.
static func sfx_recipes(root_midi: int) -> Array:
	var r := root_midi
	return [
		["tap", _sfx_tap.bind(r)],
		["rotate", _sfx_simple_pluck.bind(r + 19, 0.11, 0.25, 0.5)],
		["ui", _sfx_simple_pluck.bind(r + 31, 0.05, 0.1, 0.35)],
		["connect", _sfx_connect.bind(r)],
		["disconnect", _sfx_simple_pluck.bind(r + 7, 0.1, 0.1, 0.3)],
		["denied", _sfx_denied.bind(r)],
		["hint", _sfx_hint.bind(r)],
		["energy", _sfx_energy.bind(r)],
		["achievement", _sfx_achievement.bind(r)],
		["solve", _sfx_solve.bind(r)],
		["boss", _sfx_boss.bind(r)],
	]


static func _sfx_tap(r: int) -> AudioStreamWAV:
	var rng := SeededRng.new(r * 7919)
	var tap := buffer(0.09)
	mix(tap, noise(0.03, 5000.0, 0.0005, rng), 0.0, 0.35)
	mix(tap, pluck(midi_freq(r + 24), 0.08, 0.2), 0.0, 0.45)
	normalize(tap, 0.55)
	return to_wav(tap, SFX_RATE)


static func _sfx_simple_pluck(midi: int, seconds: float, brightness: float, peak: float) -> AudioStreamWAV:
	var b := pluck(midi_freq(midi), seconds, brightness)
	normalize(b, peak)
	return to_wav(b, SFX_RATE)


static func _sfx_connect(r: int) -> AudioStreamWAV:
	var b := buffer(0.45)
	mix(b, bell(midi_freq(r + 24), 0.4), 0.0, 0.5)
	mix(b, bell(midi_freq(r + 31), 0.38), 0.05, 0.4)
	normalize(b, 0.55)
	return to_wav(b, SFX_RATE)


static func _sfx_denied(r: int) -> AudioStreamWAV:
	var rng := SeededRng.new(r * 31)
	var b := buffer(0.2)
	mix(b, thud(0.18), 0.0, 0.8)
	mix(b, noise(0.05, 900.0, 0.001, rng), 0.0, 0.3)
	normalize(b, 0.6)
	return to_wav(b, SFX_RATE)


static func _sfx_hint(r: int) -> AudioStreamWAV:
	var b := buffer(0.6)
	mix(b, bell(midi_freq(r + 31), 0.5), 0.0, 0.5)
	mix(b, bell(midi_freq(r + 36), 0.5), 0.08, 0.45)
	normalize(b, 0.5)
	return to_wav(b, SFX_RATE)


static func _sfx_energy(r: int) -> AudioStreamWAV:
	var b := noise(0.5, 2200.0, 0.3, SeededRng.new(r * 97))
	normalize(b, 0.35)
	return to_wav(b, SFX_RATE)


static func _sfx_achievement(r: int) -> AudioStreamWAV:
	var b := buffer(1.2)
	var steps: Array[int] = [0, 4, 7]
	for i in steps.size():
		mix(b, bell(midi_freq(r + 24 + steps[i]), 0.9), i * 0.09, 0.35)
	normalize(b, 0.6)
	return to_wav(b, SFX_RATE)


## Musical resolution: rising arpeggio landing on the tonic.
static func _sfx_solve(r: int) -> AudioStreamWAV:
	var b := buffer(1.9)
	var arp: Array[int] = [0, 3, 7, 12, 15, 19, 24]
	for i in arp.size():
		mix(b, pluck(midi_freq(r + 12 + arp[i]), 0.9, 0.4), i * 0.075, 0.42)
		mix(b, bell(midi_freq(r + 24 + arp[i]), 0.7), i * 0.075 + 0.02, 0.12)
	mix(b, bell(midi_freq(r + 36), 1.3), arp.size() * 0.075, 0.35)
	mix(b, bell(midi_freq(r + 43), 1.2), arp.size() * 0.075 + 0.05, 0.25)
	normalize(b, 0.7)
	return to_wav(b, SFX_RATE)


static func _sfx_boss(r: int) -> AudioStreamWAV:
	var b := buffer(3.0)
	var arp: Array[int] = [0, 7, 12, 15, 19, 24, 27, 31, 36]
	for i in arp.size():
		mix(b, pluck(midi_freq(r + arp[i]), 1.2, 0.5), i * 0.11, 0.4)
		mix(b, bell(midi_freq(r + 12 + arp[i]), 1.0), i * 0.11 + 0.03, 0.15)
	mix(b, bell(midi_freq(r + 48), 1.8), 1.1, 0.3)
	normalize(b, 0.75)
	return to_wav(b, SFX_RATE)


## Triad built on a scale degree of the natural minor scale.
static func chord(root_midi: int, degree: int) -> Array[int]:
	var out: Array[int] = []
	for k in [0, 2, 4]:
		var idx: int = degree + k
		var octave := idx / MINOR.size()
		out.append(root_midi + MINOR[idx % MINOR.size()] + 12 * octave)
	return out
