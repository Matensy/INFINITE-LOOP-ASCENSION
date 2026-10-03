extends Node
## Autoload "Themes": the active visual theme (colours, background, UI
## styles). Gameplay never depends on the theme; only presentation does.

signal theme_changed(palette: Palette)

var palette: Palette = Palette.new()
var ui_theme: Theme
var theme_id: String = ""


func _ready() -> void:
	ThemeCatalog.load_catalog()
	var save := get_node_or_null("/root/Save")
	if save:
		save.settings_changed.connect(_on_setting)
	apply(_initial_theme())


func _initial_theme() -> String:
	var choice := user_choice()
	return choice if choice != "auto" else ThemeCatalog.DEFAULT_ID


## The user's theme setting ("auto" = follow each puzzle's theme).
func user_choice() -> String:
	var save := get_node_or_null("/root/Save")
	return str(save.setting("theme", "auto")) if save else "auto"


## Theme to show for a puzzle, honouring the user's override.
func resolve_for_puzzle(puzzle_theme: String) -> String:
	var choice := user_choice()
	if choice != "auto":
		return choice
	return puzzle_theme if puzzle_theme != "" else ThemeCatalog.DEFAULT_ID


func apply(id: String, force: bool = false) -> void:
	if id == theme_id and not force:
		return
	theme_id = id
	var save := get_node_or_null("/root/Save")
	var hc: bool = save.setting("high_contrast", false) if save else false
	var cb: bool = save.setting("colorblind", false) if save else false
	palette = Palette.from_theme(ThemeCatalog.get_theme(id), hc, cb)
	ui_theme = UiTheme.build(palette)
	if is_inside_tree():
		get_tree().root.theme = ui_theme
	var audio := get_node_or_null("/root/Audio")
	if audio:
		audio.set_theme(id)
	theme_changed.emit(palette)


func _on_setting(key: String, _value: Variant) -> void:
	if key in ["high_contrast", "colorblind"]:
		apply(theme_id, true)
	elif key == "theme":
		var choice := user_choice()
		apply(choice if choice != "auto" else ThemeCatalog.DEFAULT_ID)
