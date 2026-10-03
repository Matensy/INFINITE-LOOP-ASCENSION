class_name MusicEngine
extends RefCounted
## Real-time generative ambient music written into an AudioStreamGenerator
## from the main thread (a few hundred samples per frame).
##
## Three layers follow the game: a breathing pad (always), a soft arpeggio
## that grows with puzzle complexity and a high shimmer that rises as the
## board approaches its solution. Chords follow a i-VI-III-VII progression
## in the key of the current theme.

const RATE := 22050.0
const CHORD_SECONDS := 4.0
const STEPS_PER_CHORD := 8
const MAX_PLUCKS := 4
const MAX_BELLS := 2
const PATTERN: Array[int] = [0, 1, 2, 1, 0, 2, 1, 2]

var root_midi: int = 57
var intensity: float = 0.3
var progress: float = 0.0
var master: float = 1.0

var _t: int = 0
var _chord_len: int = int(CHORD_SECONDS * RATE)
var _step_len: int = int(CHORD_SECONDS * RATE) / STEPS_PER_CHORD
var _chord_index := 0
var _pad_inc := PackedFloat32Array()
var _pad_phase := PackedFloat32Array()
var _chord_notes: Array[int] = []
var _pluck_inc := PackedFloat32Array()
var _pluck_phase := PackedFloat32Array()
var _pluck_env := PackedFloat32Array()
var _pluck_decay := PackedFloat32Array()
var _bell_freq := PackedFloat32Array()
var _bell_t := PackedFloat32Array()
var _bell_env := PackedFloat32Array()
var _arp_gain := 0.0
var _shimmer_gain := 0.0
var _rng := SeededRng.new(97)


func _init() -> void:
	_pad_inc.resize(6)
	_pad_phase.resize(6)
	for arr in [_pluck_inc, _pluck_phase, _pluck_env, _pluck_decay]:
		(arr as PackedFloat32Array).resize(MAX_PLUCKS)
	for arr in [_bell_freq, _bell_t, _bell_env]:
		(arr as PackedFloat32Array).resize(MAX_BELLS)
	_set_chord(0)


func set_key(midi: int) -> void:
	root_midi = midi


func _set_chord(index: int) -> void:
	_chord_index = index % Synth.PROGRESSION.size()
	_chord_notes = Synth.chord(root_midi, Synth.PROGRESSION[_chord_index])
	for i in 3:
		var f := Synth.midi_freq(_chord_notes[i] - 12)
		_pad_inc[i * 2] = f * 0.9965 / RATE
		_pad_inc[i * 2 + 1] = f * 1.0035 / RATE


func _trigger_pluck() -> void:
	var step := (_t / _step_len) % STEPS_PER_CHORD
	var note: int = _chord_notes[PATTERN[step]] + 12 + (12 if step == 5 else 0)
	var slot := 0
	var lowest := 99.0
	for i in MAX_PLUCKS:
		if _pluck_env[i] < lowest:
			lowest = _pluck_env[i]
			slot = i
	_pluck_inc[slot] = Synth.midi_freq(note) / RATE
	_pluck_phase[slot] = 0.0
	_pluck_env[slot] = 1.0
	_pluck_decay[slot] = exp(-6.0 / (0.55 * RATE))


func _trigger_bell() -> void:
	var degree: int = Synth.MINOR[_rng.range_int(0, Synth.MINOR.size() - 1)]
	var slot := 0 if _bell_env[0] < _bell_env[1] else 1
	_bell_freq[slot] = Synth.midi_freq(root_midi + 24 + degree)
	_bell_t[slot] = 0.0
	_bell_env[slot] = 1.0


## Writes up to `max_frames` frames into the generator playback.
func fill(playback: AudioStreamGeneratorPlayback, max_frames: int) -> void:
	var n := mini(playback.get_frames_available(), max_frames)
	if n <= 0:
		return
	var target_arp := clampf(intensity * 1.4, 0.0, 1.0) * 0.32
	var target_shimmer := clampf((progress - 0.5) * 2.0 + intensity * 0.3, 0.0, 1.0) * 0.22
	var buf := PackedVector2Array()
	buf.resize(n)
	var bell_step := 1.0 / RATE
	for i in n:
		if _t % _chord_len == 0:
			_set_chord(_t / _chord_len)
		if _t % _step_len == 0:
			_arp_gain = lerpf(_arp_gain, target_arp, 0.25)
			_shimmer_gain = lerpf(_shimmer_gain, target_shimmer, 0.25)
			if _arp_gain > 0.02:
				_trigger_pluck()
			if _shimmer_gain > 0.02 and _rng.chance(0.18):
				_trigger_bell()
		# Pad: detuned triangles with a breathing envelope per chord.
		var pos := float(_t % _chord_len) / RATE
		var breath := minf(1.0, pos / 1.0) * clampf((CHORD_SECONDS - pos) / 0.8, 0.25, 1.0)
		var pad := 0.0
		for v in 6:
			var ph := _pad_phase[v] + _pad_inc[v]
			ph -= floorf(ph)
			_pad_phase[v] = ph
			pad += 1.0 - 4.0 * absf(ph - 0.5)
		var s := pad * 0.035 * breath
		# Arpeggio plucks.
		for v in MAX_PLUCKS:
			var env := _pluck_env[v]
			if env < 0.001:
				continue
			var ph := _pluck_phase[v] + _pluck_inc[v]
			ph -= floorf(ph)
			_pluck_phase[v] = ph
			s += sin(TAU * ph) * env * _arp_gain * 0.5
			_pluck_env[v] = env * _pluck_decay[v]
		# Shimmer bells (light FM).
		for v in MAX_BELLS:
			var env := _bell_env[v]
			if env < 0.001:
				continue
			var t := _bell_t[v]
			var mod := sin(TAU * _bell_freq[v] * 1.41 * t) * 2.0 * env
			s += sin(TAU * _bell_freq[v] * t + mod) * env * _shimmer_gain * 0.4
			_bell_t[v] = t + bell_step
			_bell_env[v] = env * 0.99985
		s *= master
		s = s / (1.0 + absf(s))
		buf[i] = Vector2(s, s)
		_t += 1
	playback.push_buffer(buf)
