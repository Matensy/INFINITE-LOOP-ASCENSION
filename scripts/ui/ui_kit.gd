class_name UiKit
extends RefCounted
## Small factory helpers so screens build consistent UI in code.


static func label(text: String, size: int = 28, color: Color = Color(0, 0, 0, 0), font: Font = null,
		align: int = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	if color.a > 0.0:
		l.add_theme_color_override("font_color", color)
	if font:
		l.add_theme_font_override("font", font)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func title(text: String, size: int = 44, color: Color = Color(0, 0, 0, 0)) -> Label:
	var l := label(text, size, color, UiTheme.title_font())
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l


static func button(text: String, callback: Callable = Callable(), min_height: int = 92) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, min_height)
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = true
	if callback.is_valid():
		b.pressed.connect(callback)
	b.pressed.connect(_click)
	return b


static func primary_button(text: String, callback: Callable = Callable(), accent: Color = Color(0.37, 0.97, 1.0)) -> Button:
	var b := button(text, callback, 108)
	b.add_theme_font_override("font", UiTheme.title_bold_font())
	b.add_theme_font_size_override("font_size", 32)
	var normal := UiTheme.box(Color(accent, 0.16), Color(accent, 0.95), 3, 22)
	var hover := UiTheme.box(Color(accent, 0.26), accent.lerp(Color.WHITE, 0.3), 3, 22)
	var pressed := UiTheme.box(Color(accent, 0.38), Color.WHITE, 3, 22)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	return b


static func icon_button(symbol: String, callback: Callable = Callable(), size: int = 84) -> Button:
	var b := button(symbol, callback, size)
	b.custom_minimum_size = Vector2(size, size)
	b.clip_text = false
	b.add_theme_font_size_override("font_size", 34)
	# Narrow side margins so the glyph is never clipped (uses the app theme).
	var tree := Engine.get_main_loop() as SceneTree
	var theme: Theme = tree.root.theme if tree else null
	if theme:
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			if not theme.has_stylebox(state, "Button"):
				continue
			var box := theme.get_stylebox(state, "Button").duplicate() as StyleBox
			box.content_margin_left = 4
			box.content_margin_right = 4
			b.add_theme_stylebox_override(state, box)
	return b


static func _click() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var audio := tree.root.get_node_or_null("Audio")
	if audio:
		audio.play("ui")
	var haptics := tree.root.get_node_or_null("Haptics")
	if haptics:
		haptics.pulse_ui()


static func vbox(separation: int = 14) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", separation)
	return v


static func hbox(separation: int = 14) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", separation)
	return h


static func spacer(height: float = 0.0, expand: bool = false) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func margin(child: Control, left: int, top: int, right: int, bottom: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", left)
	m.add_theme_constant_override("margin_top", top)
	m.add_theme_constant_override("margin_right", right)
	m.add_theme_constant_override("margin_bottom", bottom)
	if child:
		m.add_child(child)
	return m


static func full_rect(c: Control) -> Control:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_left = 0
	c.offset_top = 0
	c.offset_right = 0
	c.offset_bottom = 0
	return c


static func panel(child: Control = null) -> PanelContainer:
	var p := PanelContainer.new()
	if child:
		p.add_child(child)
	return p


## Two-column "LABEL ...... value" row.
static func stat_row(key_text: String, value_text: String, dim: Color, text_color: Color) -> HBoxContainer:
	var row := hbox(8)
	var k := label(key_text, 24, dim, null, HORIZONTAL_ALIGNMENT_LEFT)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	k.autowrap_mode = TextServer.AUTOWRAP_OFF
	var v := label(value_text, 26, text_color, UiTheme.bold_font(), HORIZONTAL_ALIGNMENT_RIGHT)
	v.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(k)
	row.add_child(v)
	return row


## Screen-space safe area (notch, rounded corners, nav bar) converted to
## viewport units: returns margins as Rect2(left, top, right, bottom).
static func safe_margins(viewport: Viewport) -> Rect2:
	var win_size := Vector2(DisplayServer.window_get_size())
	var vp_size := viewport.get_visible_rect().size
	if win_size.x <= 0 or win_size.y <= 0:
		return Rect2()
	var safe := Rect2(DisplayServer.get_display_safe_area())
	var screen := Vector2(DisplayServer.screen_get_size())
	if safe.size.x <= 0 or safe.size.y <= 0 or screen.x <= 0:
		return Rect2()
	var sx := vp_size.x / win_size.x
	var sy := vp_size.y / win_size.y
	var left := maxf(0.0, safe.position.x) * sx
	var top := maxf(0.0, safe.position.y) * sy
	var right := maxf(0.0, screen.x - safe.end.x) * sx
	var bottom := maxf(0.0, screen.y - safe.end.y) * sy
	return Rect2(left, top, right, bottom)
