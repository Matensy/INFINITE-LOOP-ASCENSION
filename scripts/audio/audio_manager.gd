extends Node
## Autoload "Audio": procedural SFX + adaptive layered music.
## Sounds are synthesised on a worker thread at start-up (and when the theme
## key changes); the game never waits for audio.

const POOL_SIZE := 10
## Root note (MIDI) per theme so music and effects match the visual mood.
const THEME_KEYS := {
	"cyber": 57, "void": 50, "ocean": 52, "forest": 55, "galaxy": 53, "crystal": 59,
	"digital": 54, "inferno": 52, "ancient": 50, "celestial": 60, "quantum": 56, "monochrome": 57,
}
const MUSIC_LAYERS: Array[String] = ["pad", "arp", "shimmer"]

var enabled := true
var _sfx: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _music: Dictionary = {}
var _music_cache: Dictionary = {}
var _sfx_cache: Dictionary = {}
var _key := -1
var _want_key := -1
var _task := -1
var _task_key := -1
var _task_result: Dictionary = {}
var _task_mutex := Mutex.new()
var _intensity := 0.3
var _progress := 0.0
var _duck := 0.0


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
	for layer in MUSIC_LAYERS:
		var m := AudioStreamPlayer.new()
		m.bus = "Music"
		m.volume_db = -60.0
		add_child(m)
		_music[layer] = m
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
	var music_on: bool = save.setting("music", true) if save else true
	var sfx_vol: float = save.setting("sfx_volume", 0.8) if save else 0.8
	var music_vol: float = save.setting("music_volume", 0.45) if save else 0.45
	var sfx_idx := AudioServer.get_bus_index("SFX")
	var mus_idx := AudioServer.get_bus_index("Music")
	AudioServer.set_bus_mute(sfx_idx, not sfx_on)
	AudioServer.set_bus_mute(mus_idx, not music_on)
	AudioServer.set_bus_volume_db(sfx_idx, linear_to_db(maxf(sfx_vol, 0.001)))
	AudioServer.set_bus_volume_db(mus_idx, linear_to_db(maxf(music_vol, 0.001)))


## Switches the musical key to match a theme (synthesised in background).
func set_theme(theme_id: String) -> void:
	if not enabled:
		return
	_want_key = int(THEME_KEYS.get(theme_id, 57))
	_service_synth()


func _service_synth() -> void:
	if _want_key == _key:
		return
	if _music_cache.has(_want_key):
		_install(_want_key)
	elif _task < 0:
		_task_key = _want_key
		_task = WorkerThreadPool.add_task(_synth_task.bind(_task_key), false, "audio synth")


## Runs on a worker thread; only touches its own local data until stored.
func _synth_task(key: int) -> void:
	var sfx := Synth.make_sfx(key)
	var music := Synth.make_music(key)
	_task_mutex.lock()
	_task_result = {"sfx": sfx, "music": music}
	_task_mutex.unlock()


func _process(delta: float) -> void:
	if not enabled:
		return
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_task_mutex.lock()
		var res := _task_result
		_task_result = {}
		_task_mutex.unlock()
		if not res.is_empty():
			_sfx_cache[_task_key] = res["sfx"]
			_music_cache[_task_key] = res["music"]
		_service_synth()
	_duck = maxf(0.0, _duck - delta)
	_update_music_levels(delta)


func _install(key: int) -> void:
	_key = key
	_sfx = _sfx_cache[key]
	var music: Dictionary = _music_cache[key]
	for layer in MUSIC_LAYERS:
		var p: AudioStreamPlayer = _music[layer]
		p.stream = music.get(layer)
		p.play()


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
	_intensity = clampf(complexity, 0.0, 1.0)
	_progress = clampf(progress, 0.0, 1.0)


## Lowers the music briefly so a resolution sting can be heard.
func duck(seconds: float) -> void:
	_duck = maxf(_duck, seconds)


func _update_music_levels(delta: float) -> void:
	var duck_db := -14.0 if _duck > 0.0 else 0.0
	var targets := {
		"pad": -9.0 + duck_db,
		"arp": lerpf(-40.0, -11.0, clampf(_intensity * 1.4, 0.0, 1.0)) + duck_db,
		"shimmer": lerpf(-40.0, -13.0, clampf((_progress - 0.5) * 2.0 + _intensity * 0.3, 0.0, 1.0)) + duck_db,
	}
	for layer in MUSIC_LAYERS:
		var p: AudioStreamPlayer = _music[layer]
		p.volume_db = move_toward(p.volume_db, targets[layer], delta * 18.0)
