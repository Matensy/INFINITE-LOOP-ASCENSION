class_name Synth
extends RefCounted
## Tiny offline synthesiser. All sounds and music loops are generated at
## runtime from code, so the APK ships no audio files at all.

const SFX_RATE := 22050
const PAD_RATE := 11025
const LOOP_SECONDS := 16.0
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


## All sound effects, tuned to a root note so effects and music agree.
static func make_sfx(root_midi: int) -> Dictionary:
	var rng := SeededRng.new(root_midi * 7919)
	var r := root_midi
	var sfx := {}

	var tap := buffer(0.09)
	mix(tap, noise(0.03, 5000.0, 0.0005, rng), 0.0, 0.35)
	mix(tap, pluck(midi_freq(r + 24), 0.08, 0.2), 0.0, 0.45)
	normalize(tap, 0.55)
	sfx["tap"] = to_wav(tap, SFX_RATE)

	var rot := pluck(midi_freq(r + 19), 0.11, 0.25)
	normalize(rot, 0.5)
	sfx["rotate"] = to_wav(rot, SFX_RATE)

	var connect := buffer(0.45)
	mix(connect, bell(midi_freq(r + 24), 0.4), 0.0, 0.5)
	mix(connect, bell(midi_freq(r + 31), 0.38), 0.05, 0.4)
	normalize(connect, 0.55)
	sfx["connect"] = to_wav(connect, SFX_RATE)

	var disc := pluck(midi_freq(r + 7), 0.1, 0.1)
	normalize(disc, 0.3)
	sfx["disconnect"] = to_wav(disc, SFX_RATE)

	var denied := buffer(0.2)
	mix(denied, thud(0.18), 0.0, 0.8)
	mix(denied, noise(0.05, 900.0, 0.001, rng), 0.0, 0.3)
	normalize(denied, 0.6)
	sfx["denied"] = to_wav(denied, SFX_RATE)

	var energy := noise(0.5, 2200.0, 0.3, rng)
	normalize(energy, 0.35)
	sfx["energy"] = to_wav(energy, SFX_RATE)

	var hint := buffer(0.6)
	mix(hint, bell(midi_freq(r + 31), 0.5), 0.0, 0.5)
	mix(hint, bell(midi_freq(r + 36), 0.5), 0.08, 0.45)
	normalize(hint, 0.5)
	sfx["hint"] = to_wav(hint, SFX_RATE)

	var ui := pluck(midi_freq(r + 31), 0.05, 0.1)
	normalize(ui, 0.35)
	sfx["ui"] = to_wav(ui, SFX_RATE)

	# Musical resolution: rising arpeggio landing on the tonic.
	var solve := buffer(1.9)
	var arp: Array[int] = [0, 3, 7, 12, 15, 19, 24]
	for i in arp.size():
		mix(solve, pluck(midi_freq(r + 12 + arp[i]), 0.9, 0.4), i * 0.075, 0.42)
		mix(solve, bell(midi_freq(r + 24 + arp[i]), 0.7), i * 0.075 + 0.02, 0.12)
	mix(solve, bell(midi_freq(r + 36), 1.3), arp.size() * 0.075, 0.35)
	mix(solve, bell(midi_freq(r + 43), 1.2), arp.size() * 0.075 + 0.05, 0.25)
	normalize(solve, 0.7)
	sfx["solve"] = to_wav(solve, SFX_RATE)

	var boss := buffer(3.0)
	var boss_arp: Array[int] = [0, 7, 12, 15, 19, 24, 27, 31, 36]
	for i in boss_arp.size():
		mix(boss, pluck(midi_freq(r + boss_arp[i]), 1.2, 0.5), i * 0.11, 0.4)
		mix(boss, bell(midi_freq(r + 12 + boss_arp[i]), 1.0), i * 0.11 + 0.03, 0.15)
	mix(boss, bell(midi_freq(r + 48), 1.8), 1.1, 0.3)
	normalize(boss, 0.75)
	sfx["boss"] = to_wav(boss, SFX_RATE)

	var ach := buffer(1.2)
	for i in 3:
		mix(ach, bell(midi_freq(r + 24 + [0, 4, 7][i]), 0.9), i * 0.09, 0.35)
	normalize(ach, 0.6)
	sfx["achievement"] = to_wav(ach, SFX_RATE)
	return sfx


## Three synchronised 16 s loops: pad (always), arp and shimmer (adaptive).
static func make_music(root_midi: int) -> Dictionary:
	var rng := SeededRng.new(root_midi * 104729)
	var chord_len := LOOP_SECONDS / PROGRESSION.size()

	# Pad: detuned triangle chords, smooth crossfade between chords.
	var pad := buffer(LOOP_SECONDS, PAD_RATE)
	for ci in PROGRESSION.size():
		var notes := _chord(root_midi - 12, PROGRESSION[ci])
		var start := int(ci * chord_len * PAD_RATE)
		var length := int((chord_len + 1.5) * PAD_RATE)
		for note in notes:
			for detune in [-0.06, 0.06]:
				var f := midi_freq(note + detune)
				var phase := rng.next_float()
				for i in length:
					var t := float(i) / PAD_RATE
					phase += f / PAD_RATE
					var p := phase - floorf(phase)
					var tri := 1.0 - 4.0 * absf(p - 0.5)
					var env := minf(1.0, t / 1.2) * clampf((chord_len + 1.5 - t) / 1.5, 0.0, 1.0)
					var j := (start + i) % pad.size()
					pad[j] += tri * env * 0.12
	normalize(pad, 0.5)

	# Arp: chord tones in a gentle 8th-note pattern.
	var arp := buffer(LOOP_SECONDS)
	var step := chord_len / 8.0
	for ci in PROGRESSION.size():
		var notes := _chord(root_midi + 12, PROGRESSION[ci])
		var pattern: Array[int] = [0, 1, 2, 1, 0, 2, 1, 2]
		for k in 8:
			var note: int = notes[pattern[k]] + (12 if k == 5 else 0)
			mix(arp, pluck(midi_freq(note), 0.55, 0.3), ci * chord_len + k * step, 0.3, SFX_RATE, true)
	normalize(arp, 0.4)

	# Shimmer: sparse high bells on scale tones.
	var shimmer := buffer(LOOP_SECONDS)
	for k in 14:
		var degree: int = MINOR[rng.range_int(0, MINOR.size() - 1)]
		var at := rng.range_float(0.0, LOOP_SECONDS - 0.5)
		mix(shimmer, bell(midi_freq(root_midi + 24 + degree), 1.6), at, 0.25, SFX_RATE, true)
	normalize(shimmer, 0.3)

	return {
		"pad": to_wav(pad, PAD_RATE, true),
		"arp": to_wav(arp, SFX_RATE, true),
		"shimmer": to_wav(shimmer, SFX_RATE, true),
	}


## Triad built on a scale degree of the natural minor scale.
static func _chord(root_midi: int, degree: int) -> Array[int]:
	var out: Array[int] = []
	for k in [0, 2, 4]:
		var idx: int = degree + k
		var octave := idx / MINOR.size()
		out.append(root_midi + MINOR[idx % MINOR.size()] + 12 * octave)
	return out
