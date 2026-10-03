class_name UiTheme
extends RefCounted
## Builds the Godot Theme resource for all Controls from a Palette, so the UI
## restyles itself whenever the visual theme changes.

const BODY_FONT := "res://assets/fonts/Exo2-Regular.woff2"
const BODY_BOLD_FONT := "res://assets/fonts/Exo2-Bold.woff2"
const BODY_SEMI_FONT := "res://assets/fonts/Exo2-SemiBold.woff2"
const TITLE_FONT := "res://assets/fonts/Orbitron-Black.woff2"
const TITLE_BOLD_FONT := "res://assets/fonts/Orbitron-Bold.woff2"

const FONT_SIZE := 28
const BUTTON_FONT_SIZE := 30
const RADIUS := 18

static var _fonts: Dictionary = {}


static func font(path: String) -> Font:
	if _fonts.has(path):
		return _fonts[path]
	var f: Font = load(path) if ResourceLoader.exists(path) else ThemeDB.fallback_font
	_fonts[path] = f
	return f


static func title_font() -> Font:
	return font(TITLE_FONT)


static func title_bold_font() -> Font:
	return font(TITLE_BOLD_FONT)


static func body_font() -> Font:
	return font(BODY_FONT)


static func bold_font() -> Font:
	return font(BODY_BOLD_FONT)


static func semi_font() -> Font:
	return font(BODY_SEMI_FONT)


static func box(bg: Color, border: Color, border_w: int = 2, radius: int = RADIUS, margin_h: float = 24.0, margin_v: float = 14.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = margin_h
	s.content_margin_right = margin_h
	s.content_margin_top = margin_v
	s.content_margin_bottom = margin_v
	s.anti_aliasing = true
	return s


static func build(p: Palette) -> Theme:
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = FONT_SIZE

	t.set_color("font_color", "Label", p.ui_text)

	var panel_bg := Color(p.panel, 0.9)
	var normal := box(Color(p.panel, 0.82), Color(p.ui_accent, 0.45))
	var hover := box(Color(p.panel.lightened(0.08), 0.92), Color(p.ui_accent, 0.9))
	var pressed := box(Color(p.ui_accent, 0.22), p.ui_accent)
	var disabled := box(Color(p.panel, 0.4), Color(p.ui_dim, 0.25))
	for cls in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", cls, normal)
		t.set_stylebox("hover", cls, hover)
		t.set_stylebox("pressed", cls, pressed)
		t.set_stylebox("hover_pressed", cls, pressed)
		t.set_stylebox("disabled", cls, disabled)
		t.set_stylebox("focus", cls, StyleBoxEmpty.new())
		t.set_color("font_color", cls, p.ui_text)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, p.ui_accent.lerp(Color.WHITE, 0.5))
		t.set_color("font_focus_color", cls, p.ui_text)
		t.set_color("font_disabled_color", cls, Color(p.ui_dim, 0.6))
		t.set_font("font", cls, semi_font())
		t.set_font_size("font_size", cls, BUTTON_FONT_SIZE)

	t.set_stylebox("panel", "PanelContainer", box(panel_bg, Color(p.ui_accent, 0.28), 2, 26, 30, 26))
	t.set_stylebox("panel", "Panel", box(panel_bg, Color(p.ui_accent, 0.28), 2, 26, 30, 26))
	t.set_stylebox("panel", "PopupPanel", box(panel_bg, Color(p.ui_accent, 0.4), 2, 20, 16, 12))
	t.set_stylebox("panel", "PopupMenu", box(panel_bg, Color(p.ui_accent, 0.4), 2, 16, 16, 10))
	t.set_color("font_color", "PopupMenu", p.ui_text)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_stylebox("hover", "PopupMenu", box(Color(p.ui_accent, 0.2), Color(0, 0, 0, 0), 0, 10, 8, 6))
	t.set_font_size("font_size", "PopupMenu", FONT_SIZE)

	var edit := box(Color(p.bg_bottom, 0.9), Color(p.ui_accent, 0.6), 2, 14, 18, 14)
	t.set_stylebox("normal", "LineEdit", edit)
	t.set_stylebox("focus", "LineEdit", box(Color(p.bg_bottom, 0.95), p.ui_accent, 2, 14, 18, 14))
	t.set_color("font_color", "LineEdit", p.ui_text)
	t.set_color("caret_color", "LineEdit", p.ui_accent)
	t.set_color("font_placeholder_color", "LineEdit", Color(p.ui_dim, 0.8))
	t.set_font_size("font_size", "LineEdit", 30)

	t.set_stylebox("normal", "TextEdit", edit)
	t.set_stylebox("focus", "TextEdit", edit)
	t.set_color("font_color", "TextEdit", p.ui_text)
	t.set_font_size("font_size", "TextEdit", 20)

	for cls in ["CheckButton", "CheckBox"]:
		t.set_color("font_color", cls, p.ui_text)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, p.ui_text)
		t.set_stylebox("focus", cls, StyleBoxEmpty.new())
		t.set_font_size("font_size", cls, FONT_SIZE)

	var slider := StyleBoxFlat.new()
	slider.bg_color = Color(p.ui_dim, 0.35)
	slider.set_corner_radius_all(6)
	slider.content_margin_top = 6
	slider.content_margin_bottom = 6
	t.set_stylebox("slider", "HSlider", slider)
	var fill := slider.duplicate() as StyleBoxFlat
	fill.bg_color = Color(p.ui_accent, 0.85)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)

	var bar_bg := box(Color(p.ui_dim, 0.2), Color(0, 0, 0, 0), 0, 8, 0, 0)
	var bar_fill := box(Color(p.ui_accent, 0.9), Color(0, 0, 0, 0), 0, 8, 0, 0)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	t.set_color("font_color", "ProgressBar", p.ui_text)

	t.set_constant("separation", "VBoxContainer", 14)
	t.set_constant("separation", "HBoxContainer", 14)
	var sep := StyleBoxLine.new()
	sep.color = Color(p.ui_accent, 0.2)
	sep.thickness = 2
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	return t
