class_name UiKit
extends RefCounted
## Factory helpers so every screen builds the same modern UI in code:
## gradient pills, frosted cards, circular icon buttons, chips.

const GRADIENT_TEXT_SHADER := "res://shaders/gradient_text.gdshader"

static var _gradient_shader: Shader


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
	# Texts arrive already translated; auto-translation would turn captions
	# such as "TIME" (also a key) back into "Time".
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	return l


static func title(text: String, size: int = 44, color: Color = Color(0, 0, 0, 0)) -> Label:
	var l := label(text, size, color, UiTheme.bold_font())
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l


## Small uppercase caption ("SECTION", overlines).
static func caption(text: String, color: Color, size: int = 20, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := label(text.to_upper(), size, color, UiTheme.semi_font(), align)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l


## Title with an animated horizontal gradient.
static func gradient_title(text: String, size: int, a: Color, b: Color) -> Label:
	var l := title(text, size, Color.WHITE)
	if _gradient_shader == null:
		_gradient_shader = load(GRADIENT_TEXT_SHADER)
	var mat := ShaderMaterial.new()
	mat.shader = _gradient_shader
	mat.set_shader_parameter("color_a", a)
	mat.set_shader_parameter("color_b", b)
	l.material = mat
	l.resized.connect(func(): mat.set_shader_parameter("width", l.size.x))
	return l


## Frosted secondary pill.
static func button(text: String, callback: Callable = Callable(), min_height: int = 88) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, min_height)
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = true
	if callback.is_valid():
		b.pressed.connect(callback)
	b.pressed.connect(_click)
	return b


## Primary call-to-action: gradient pill with glow and dark text.
static func primary_button(text: String, callback: Callable = Callable(), a: Color = Color("#5ef7ff"),
		b: Color = Color("#a78bfa"), min_height: int = 104) -> Button:
	var btn := button(text, callback, min_height)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		btn.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var dark := Color("#0a0b1f")
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		btn.add_theme_color_override(key, dark)
	btn.add_theme_font_override("font", UiTheme.bold_font())
	btn.add_theme_font_size_override("font_size", 32)
	btn.add_child(PillBackground.new(a, b))
	return btn


## Circular frosted button with a vector icon.
static func icon_button(icon_name: String, callback: Callable = Callable(), size: int = 84,
		icon_color: Color = Color(1, 1, 1, 0.92)) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(size, size)
	b.focus_mode = Control.FOCUS_NONE
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(state, empty)
	b.add_child(CircleBackground.new())
	var ic := VectorIcon.new(icon_name, icon_color)
	ic.set_anchors_preset(Control.PRESET_FULL_RECT)
	var inset := size * 0.27
	ic.offset_left = inset
	ic.offset_top = inset
	ic.offset_right = -inset
	ic.offset_bottom = -inset
	b.add_child(ic)
	b.set_meta("icon", ic)
	if callback.is_valid():
		b.pressed.connect(callback)
	b.pressed.connect(_click)
	return b


## Large menu tile: frosted card with an icon above a label.
static func tile_button(icon_name: String, text: String, callback: Callable, accent: Color,
		badge: String = "") -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 150)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", UiTheme.box(Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.09), 1, 32, 0, 0))
	b.add_theme_stylebox_override("hover", UiTheme.box(Color(1, 1, 1, 0.1), Color(1, 1, 1, 0.14), 1, 32, 0, 0))
	b.add_theme_stylebox_override("pressed", UiTheme.box(Color(1, 1, 1, 0.16), Color(accent, 0.5), 1, 32, 0, 0))
	b.add_theme_stylebox_override("hover_pressed", UiTheme.box(Color(1, 1, 1, 0.16), Color(accent, 0.5), 1, 32, 0, 0))
	var col := vbox(10)
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := VectorIcon.new(icon_name, accent)
	ic.custom_minimum_size = Vector2(46, 46)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(ic)
	var l := label(text, 23, Color(1, 1, 1, 0.9), UiTheme.semi_font())
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(l)
	b.add_child(col)
	if badge != "":
		var tag := chip(badge, accent, true)
		tag.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		tag.offset_left = -72
		tag.offset_top = 10
		tag.offset_right = -10
		b.add_child(tag)
	if callback.is_valid():
		b.pressed.connect(callback)
	b.pressed.connect(_click)
	return b


## Small rounded tag.
static func chip(text: String, color: Color, filled: bool = false) -> PanelContainer:
	var p := PanelContainer.new()
	var bg := Color(color, 0.95) if filled else Color(color, 0.14)
	p.add_theme_stylebox_override("panel", UiTheme.box(bg, Color(color, 0.0 if filled else 0.3), 0 if filled else 1,
			UiTheme.PILL, 16, 5))
	var l := label(text.to_upper(), 18, Color("#0a0b1f") if filled else color.lerp(Color.WHITE, 0.35), UiTheme.semi_font())
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


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


## Frosted card with custom padding.
static func card(child: Control, radius: int = 32, pad: int = 28) -> PanelContainer:
	var c := PanelContainer.new()
	c.add_theme_stylebox_override("panel", UiTheme.box(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.08), 1, radius, pad, pad - 6))
	if child:
		c.add_child(child)
	return c


## Two-column "LABEL ...... value" row.
static func stat_row(key_text: String, value_text: String, dim: Color, text_color: Color) -> HBoxContainer:
	var row := hbox(8)
	var k := label(key_text, 24, dim, null, HORIZONTAL_ALIGNMENT_LEFT)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	k.autowrap_mode = TextServer.AUTOWRAP_OFF
	var v := label(value_text, 26, text_color, UiTheme.semi_font(), HORIZONTAL_ALIGNMENT_RIGHT)
	v.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(k)
	row.add_child(v)
	return row


## Big number over a small caption (profile / results grids).
static func stat_tile(value_text: String, caption_text: String, p: Palette, accent: Color = Color(0, 0, 0, 0)) -> PanelContainer:
	var col := vbox(2)
	var v := label(value_text, 36, accent if accent.a > 0.0 else p.ui_text, UiTheme.bold_font(), HORIZONTAL_ALIGNMENT_LEFT)
	v.autowrap_mode = TextServer.AUTOWRAP_OFF
	v.clip_text = true
	col.add_child(v)
	col.add_child(caption(caption_text, Color(p.ui_text, 0.5), 16))
	var c := card(col, 28, 24)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


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


## Letter-spaced variant of a font (FontVariation) for overlines.
static func spaced_font(base: Font, spacing: int) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = base
	fv.spacing_glyph = spacing
	return fv


## Dimmed full-screen modal with a frosted panel; returns the shade node
## (free it to close). Animates in with a fade and a slight scale.
static func modal(parent: Control, content: Control, width: float = 640.0) -> Control:
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.02, 0.62)
	full_rect(shade)
	parent.add_child(shade)
	var center := CenterContainer.new()
	full_rect(center)
	shade.add_child(center)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(minf(width, parent.get_viewport_rect().size.x - 48.0), 0)
	p.add_child(content)
	center.add_child(p)
	shade.modulate.a = 0.0
	p.scale = Vector2(0.94, 0.94)
	p.resized.connect(func(): p.pivot_offset = p.size * 0.5)
	var tw := shade.create_tween().set_parallel(true)
	tw.tween_property(shade, "modulate:a", 1.0, 0.18)
	tw.tween_property(p, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return shade


## Icon button with a caption underneath (results / pause rows).
static func labeled_icon(icon_name: String, text: String, callback: Callable, size: int = 88) -> VBoxContainer:
	var col := vbox(6)
	var b := icon_button(icon_name, callback, size)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(b)
	var l := caption(text, Color(1, 1, 1, 0.6), 16, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(l)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return col
