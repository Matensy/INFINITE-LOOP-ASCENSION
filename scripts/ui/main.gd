extends Control
## Root of the app: animated background, screen router, toasts, Android
## back handling and global accessibility settings (UI scale).

const SCREENS := {
	"menu": "res://scenes/menu/main_menu.tscn",
	"game": "res://scenes/gameplay/gameplay.tscn",
	"profile": "res://scenes/profile/profile.tscn",
	"settings": "res://scenes/settings/settings.tscn",
	"debug": "res://scenes/debug/debug_generator.tscn",
}
const BACKGROUND_SHADER := "res://shaders/background.gdshader"

var background: ColorRect
var host: Control
var current: Control
var current_name: String = ""
var _toast_layer: CanvasLayer
var _toast_box: VBoxContainer
var _bg_material: ShaderMaterial
var _history: Array[String] = []


func _ready() -> void:
	UiKit.full_rect(self)
	# Every screen passes tr() output; never re-translate node texts.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	background = ColorRect.new()
	UiKit.full_rect(background)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_material = ShaderMaterial.new()
	_bg_material.shader = load(BACKGROUND_SHADER)
	background.material = _bg_material
	add_child(background)
	host = Control.new()
	UiKit.full_rect(host)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(host)
	_toast_layer = CanvasLayer.new()
	_toast_layer.layer = 20
	add_child(_toast_layer)
	_toast_box = UiKit.vbox(10)
	_toast_box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_toast_box.offset_top = 120
	_toast_box.offset_left = 40
	_toast_box.offset_right = -40
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_layer.add_child(_toast_box)
	Themes.theme_changed.connect(_on_theme)
	Save.settings_changed.connect(_on_setting)
	_on_theme(Themes.palette)
	_apply_ui_scale()
	get_viewport().size_changed.connect(_update_aspect)
	_update_aspect()
	var start := "menu"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screen="):
			start = arg.substr(9)
	goto(start)


func goto(screen: String, remember: bool = true) -> void:
	if not SCREENS.has(screen):
		screen = "menu"
	if current:
		if current.has_method("on_leave"):
			current.on_leave()
		current.queue_free()
		if remember and current_name != "" and current_name != screen:
			_history.append(current_name)
	var scene: PackedScene = load(SCREENS[screen])
	current = scene.instantiate()
	current_name = screen
	if "main" in current:
		current.set("main", self)
	current.modulate.a = 0.0
	host.add_child(current)
	var tw := create_tween()
	tw.tween_property(current, "modulate:a", 1.0, 0.18)


func back() -> void:
	var target: String = _history.pop_back() if not _history.is_empty() else "menu"
	goto(target, false)


func toast(text: String, seconds: float = 2.2, color: Color = Color(0, 0, 0, 0)) -> void:
	var panel := PanelContainer.new()
	var st := UiTheme.box(Color(Themes.palette.panel.lerp(Color.BLACK, 0.2), 0.94), Color(1, 1, 1, 0.1), 1, 34, 30, 18)
	st.shadow_color = Color(0, 0, 0, 0.4)
	st.shadow_size = 18
	panel.add_theme_stylebox_override("panel", st)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var lbl := UiKit.label(text, 25, color if color.a > 0.0 else Themes.palette.ui_text, UiTheme.semi_font())
	panel.add_child(lbl)
	panel.modulate.a = 0.0
	_toast_box.add_child(panel)
	var tw := create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.2)
	tw.tween_interval(seconds)
	tw.tween_property(panel, "modulate:a", 0.0, 0.35)
	tw.tween_callback(panel.queue_free)


## Brief background flare used by the victory sequence.
func flare(amount: float = 1.0) -> void:
	var tw := create_tween()
	tw.tween_method(func(v: float): _bg_material.set_shader_parameter("energy", v), amount, 0.0, 1.2)


func _on_theme(p: Palette) -> void:
	_bg_material.set_shader_parameter("top_color", p.bg_top)
	_bg_material.set_shader_parameter("bottom_color", p.bg_bottom)
	_bg_material.set_shader_parameter("accent_color", p.bg_accent)
	_bg_material.set_shader_parameter("glow_a", p.lit)
	_bg_material.set_shader_parameter("glow_b", p.lit2)
	_bg_material.set_shader_parameter("style", p.bg_style)
	_apply_effects()


func _on_setting(key: String, _value: Variant) -> void:
	match key:
		"ui_scale":
			_apply_ui_scale()
		"effects", "reduce_motion":
			_apply_effects()
		"language":
			I18n.apply_setting(str(Save.setting("language", "auto")))
			goto(current_name, false)


func _apply_effects() -> void:
	var high: bool = str(Save.setting("effects", "high")) == "high"
	var calm: bool = Save.setting("reduce_motion", false)
	_bg_material.set_shader_parameter("detail", 1.0 if high and not calm else (0.5 if high else 0.0))


func _apply_ui_scale() -> void:
	get_tree().root.content_scale_factor = clampf(float(Save.setting("ui_scale", 1.0)), 0.8, 1.4)


func _update_aspect() -> void:
	var s := get_viewport().get_visible_rect().size
	if s.y > 0:
		_bg_material.set_shader_parameter("aspect", s.x / s.y)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_handle_back()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_handle_back()
		get_viewport().set_input_as_handled()


func _handle_back() -> void:
	if current and current.has_method("on_back") and current.on_back():
		return
	if current_name == "menu":
		Save.shutdown()
		get_tree().quit()
	else:
		back()
