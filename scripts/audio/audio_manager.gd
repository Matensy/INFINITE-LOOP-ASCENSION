extends Node
## Autoload "Audio": procedural SFX + real-time adaptive music.
##
## Everything runs on the main thread: sound effects are synthesised one per
## frame at start-up (and when the theme key changes) and the music is
## generated live into an AudioStreamGenerator. No worker threads are used
## (see GeneratorService for why).

const POOL_SIZE := 10
## Root note (MIDI) per theme so music and effects match the visual mood.
const THEME_KEYS := {
	"cyber": 57, "void": 50, "ocean": 52, "forest": 55, "galaxy": 53, "crystal": 59,
	"digital": 54, "inferno": 52, "ancient": 50, "celestial": 60, "quantum": 56, "monochrome": 57,
}
const MUSIC_BUFFER_SECONDS := 0.5
const MAX_FRAMES_PER_TICK := 1024

var enabled := true
var _sfx: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _key := -1
var _recipes: Array = []
var _music_player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _music := MusicEngine.new()
var _duck := 0.0
var _music_on := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	enabled = DisplayServer.get_name() != "headless"
	if not enabled:
		return
	_setup_buses()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MusicEngine.RATE
	gen.buffer_length = MUSIC_BUFFER_SECONDS
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	_music_player.stream = gen
	add_child(_music_player)
	var save := get_node_or_null("/root/Save")
	if save:
		save.settings_changed.connect(_on_setting)
	apply_volumes()
	set_theme("cyber")


func _setup_buses() -> void:
	for bus in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus)
			AudioServer.set_bus_send(idx, "Master")


func _on_setting(key: String, _value: Variant) -> void:
	if key in ["sound", "music", "sfx_volume", "music_volume"]:
		apply_volumes()


func apply_volumes() -> void:
	if not enabled:
		return
	var save := get_node_or_null("/root/Save")
	var sfx_on: bool = save.setting("sound", true) if save else true
	_music_on = save.setting("music", true) if save else true
	var sfx_vol: float = save.setting("sfx_volume", 0.8) if save else 0.8
	var music_vol: float = save.setting("music_volume", 0.45) if save else 0.45
	var sfx_idx := AudioServer.get_bus_index("SFX")
	var mus_idx := AudioServer.get_bus_index("Music")
	AudioServer.set_bus_mute(sfx_idx, not sfx_on)
	AudioServer.set_bus_mute(mus_idx, not _music_on)
	AudioServer.set_bus_volume_db(sfx_idx, linear_to_db(maxf(sfx_vol, 0.001)))
	AudioServer.set_bus_volume_db(mus_idx, linear_to_db(maxf(music_vol, 0.001)))
	if _music_on and not _music_player.playing:
		_music_player.play()
		_playback = _music_player.get_stream_playback()
	elif not _music_on and _music_player.playing:
		_music_player.stop()
		_playback = null


## Switches the musical key to match a theme; effects are re-synthesised
## progressively (one per frame).
func set_theme(theme_id: String) -> void:
	if not enabled:
		return
	var key := int(THEME_KEYS.get(theme_id, 57))
	if key == _key:
		return
	_key = key
	_music.set_key(key)
	_recipes = Synth.sfx_recipes(key)


func _process(delta: float) -> void:
	if not enabled:
		return
	if not _recipes.is_empty():
		var recipe: Array = _recipes.pop_front()
		var c: Callable = recipe[1]
		_sfx[recipe[0]] = c.call()
	_duck = maxf(0.0, _duck - delta)
	_music.master = lerpf(_music.master, 0.3 if _duck > 0.0 else 1.0, clampf(delta * 6.0, 0.0, 1.0))
	if _playback and _music_on:
		_music.fill(_playback, MAX_FRAMES_PER_TICK)


func play(name: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if not enabled or not _sfx.has(name):
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = _sfx[name]
	p.pitch_scale = pitch
	p.volume_db = volume_db
	p.play()


## complexity: 0..1 (puzzle difficulty), progress: 0..1 (fraction solved).
## More complex boards add layers; nearing the solution brings the shimmer in.
func set_intensity(complexity: float, progress: float) -> void:
	_music.intensity = clampf(complexity, 0.0, 1.0)
	_music.progress = clampf(progress, 0.0, 1.0)


## Lowers the music briefly so a resolution sting can be heard.
func duck(seconds: float) -> void:
	_duck = maxf(_duck, seconds)
