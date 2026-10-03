extends Node
## Autoload "I18n": loads data/i18n/<locale>.json into the engine's
## TranslationServer so every tr("KEY") and auto-translated Control works.
## Adding a language = adding one JSON file and listing it in LOCALES.

signal locale_changed(locale: String)

const DIR := "res://data/i18n/"
## Locales shipped now; the architecture accepts es, fr, de, ja, ko, zh, ...
const LOCALES: Array[String] = ["en_US", "pt_BR"]
const FALLBACK := "en_US"

var current: String = FALLBACK


func _ready() -> void:
	for loc in LOCALES:
		var tr_res := _load_translation(loc)
		if tr_res:
			TranslationServer.add_translation(tr_res)
	apply_setting(str(_saved_language()))


func _saved_language() -> String:
	var save := get_node_or_null("/root/Save")
	if save:
		return str(save.setting("language", "auto"))
	return "auto"


func apply_setting(language: String) -> void:
	var loc := language
	if loc == "auto" or not LOCALES.has(loc):
		loc = detect_os_locale()
	set_locale(loc)


static func detect_os_locale() -> String:
	var os_loc := OS.get_locale()
	if os_loc.begins_with("pt"):
		return "pt_BR"
	return FALLBACK


func set_locale(loc: String) -> void:
	current = loc if LOCALES.has(loc) else FALLBACK
	TranslationServer.set_locale(current)
	locale_changed.emit(current)


func _load_translation(loc: String) -> Translation:
	var path := DIR + loc + ".json"
	if not FileAccess.file_exists(path):
		GameLog.warn("I18N", "missing %s" % path)
		return null
	var d := JsonUtil.parse_dict(FileAccess.get_file_as_string(path))
	var t := Translation.new()
	t.locale = loc
	for key in d.keys():
		if str(key).begins_with("_"):
			continue
		t.add_message(StringName(key), StringName(str(d[key])))
	return t


## Formats an integer with thousands separators ("18,492" / "18.492").
func format_int(value: int) -> String:
	var s := str(absi(value))
	var sep := "." if current == "pt_BR" else ","
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = sep + out
	return ("-" if value < 0 else "") + out


static func format_time(seconds: float) -> String:
	var total := int(seconds)
	var h := total / 3600
	var m := (total / 60) % 60
	var s := total % 60
	if h > 0:
		return "%d:%02d:%02d" % [h, m, s]
	return "%02d:%02d" % [m, s]
