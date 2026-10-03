class_name UiTheme
extends RefCounted
## Builds the Godot Theme for every Control from a Palette: Outfit type,
## pill buttons, frosted panels, custom switches and sliders. The UI
## restyles itself whenever the visual theme changes.

const FONT_LIGHT := "res://assets/fonts/Outfit-Light.woff2"
const FONT_REGULAR := "res://assets/fonts/Outfit-Regular.woff2"
const FONT_SEMI := "res://assets/fonts/Outfit-SemiBold.woff2"
const FONT_BOLD := "res://assets/fonts/Outfit-ExtraBold.woff2"

const FONT_SIZE := 28
const BUTTON_FONT_SIZE := 29
const PILL := 999
const PANEL_RADIUS := 40

static var _fonts: Dictionary = {}
static var _icons: Dictionary = {}


static func font(path: String) -> Font:
	if _fonts.has(path):
		return _fonts[path]
	var f: Font = load(path) if ResourceLoader.exists(path) else ThemeDB.fallback_font
	_fonts[path] = f
	return f


static func light_font() -> Font:
	return font(FONT_LIGHT)


static func body_font() -> Font:
	return font(FONT_REGULAR)


static func semi_font() -> Font:
	return font(FONT_SEMI)


static func bold_font() -> Font:
	return font(FONT_BOLD)


## Kept for callers of the previous design.
static func title_font() -> Font:
	return bold_font()


static func title_bold_font() -> Font:
	return bold_font()


static func box(bg: Color, border: Color = Color(0, 0, 0, 0), border_w: int = 0, radius: int = PILL,
		margin_h: float = 30.0, margin_v: float = 16.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.corner_detail = 12
	s.content_margin_left = margin_h
	s.content_margin_right = margin_h
	s.content_margin_top = margin_v
	s.content_margin_bottom = margin_v
	s.anti_aliasing = true
	return s


## Frosted card used for panels, modals and list rows.
static func glass(p: Palette, radius: int = PANEL_RADIUS, strength: float = 1.0) -> StyleBoxFlat:
	var s := box(Color(p.panel.lerp(p.bg_top, 0.3), 0.86 * strength), Color(1, 1, 1, 0.08), 1, radius, 34, 30)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 24
	s.shadow_offset = Vector2(0, 10)
	return s


static func build(p: Palette) -> Theme:
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = FONT_SIZE
	t.set_color("font_color", "Label", p.ui_text)

	var normal := box(Color(1, 1, 1, 0.07), Color(1, 1, 1, 0.1), 1)
	var hover := box(Color(1, 1, 1, 0.12), Color(1, 1, 1, 0.16), 1)
	var pressed := box(Color(1, 1, 1, 0.18), Color(1, 1, 1, 0.2), 1)
	var disabled := box(Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.05), 1)
	for cls in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", cls, normal)
		t.set_stylebox("hover", cls, hover)
		t.set_stylebox("pressed", cls, pressed)
		t.set_stylebox("hover_pressed", cls, pressed)
		t.set_stylebox("disabled", cls, disabled)
		t.set_stylebox("focus", cls, StyleBoxEmpty.new())
		t.set_color("font_color", cls, Color(p.ui_text, 0.94))
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, Color.WHITE)
		t.set_color("font_hover_pressed_color", cls, Color.WHITE)
		t.set_color("font_focus_color", cls, p.ui_text)
		t.set_color("font_disabled_color", cls, Color(p.ui_text, 0.3))
		t.set_font("font", cls, semi_font())
		t.set_font_size("font_size", cls, BUTTON_FONT_SIZE)
	t.set_icon("arrow", "OptionButton", _chevron_icon(p))

	var glass_style := glass(p)
	t.set_stylebox("panel", "PanelContainer", glass_style)
	t.set_stylebox("panel", "Panel", glass_style)
	var popup := box(Color(p.panel.lerp(p.bg_top, 0.3), 0.98), Color(1, 1, 1, 0.1), 1, 28, 14, 12)
	t.set_stylebox("panel", "PopupPanel", popup)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_color("font_color", "PopupMenu", p.ui_text)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_stylebox("hover", "PopupMenu", box(Color(1, 1, 1, 0.1), Color(0, 0, 0, 0), 0, 18, 10, 8))
	t.set_font_size("font_size", "PopupMenu", FONT_SIZE)
	t.set_font("font", "PopupMenu", semi_font())
	t.set_constant("v_separation", "PopupMenu", 18)
	t.set_icon("radio_unchecked", "PopupMenu", _dot_icon(Color(1, 1, 1, 0.25), 18))
	t.set_icon("radio_checked", "PopupMenu", _dot_icon(p.lit, 18))

	var edit := box(Color(0, 0, 0, 0.28), Color(1, 1, 1, 0.12), 1, 26, 24, 16)
	t.set_stylebox("normal", "LineEdit", edit)
	t.set_stylebox("focus", "LineEdit", box(Color(0, 0, 0, 0.34), Color(p.lit, 0.8), 2, 26, 24, 16))
	t.set_color("font_color", "LineEdit", p.ui_text)
	t.set_color("caret_color", "LineEdit", p.lit)
	t.set_color("font_placeholder_color", "LineEdit", Color(p.ui_text, 0.35))
	t.set_font_size("font_size", "LineEdit", 28)

	t.set_stylebox("normal", "TextEdit", box(Color(0, 0, 0, 0.3), Color(1, 1, 1, 0.08), 1, 20, 16, 12))
	t.set_stylebox("focus", "TextEdit", box(Color(0, 0, 0, 0.3), Color(1, 1, 1, 0.08), 1, 20, 16, 12))
	t.set_color("font_color", "TextEdit", Color(p.ui_text, 0.85))
	t.set_font_size("font_size", "TextEdit", 19)

	for cls in ["CheckButton", "CheckBox"]:
		var row := box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 24, 8, 10)
		t.set_stylebox("normal", cls, row)
		t.set_stylebox("hover", cls, box(Color(1, 1, 1, 0.04), Color(0, 0, 0, 0), 0, 24, 8, 10))
		t.set_stylebox("pressed", cls, row)
		t.set_stylebox("hover_pressed", cls, box(Color(1, 1, 1, 0.04), Color(0, 0, 0, 0), 0, 24, 8, 10))
		t.set_stylebox("focus", cls, StyleBoxEmpty.new())
		t.set_color("font_color", cls, p.ui_text)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, p.ui_text)
		t.set_color("font_hover_pressed_color", cls, Color.WHITE)
		t.set_font_size("font_size", cls, FONT_SIZE)
	t.set_icon("checked", "CheckButton", _switch_icon(true, p))
	t.set_icon("unchecked", "CheckButton", _switch_icon(false, p))
	t.set_icon("checked_mirrored", "CheckButton", _switch_icon(true, p))
	t.set_icon("unchecked_mirrored", "CheckButton", _switch_icon(false, p))

	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.12)
	track.set_corner_radius_all(8)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	t.set_stylebox("slider", "HSlider", track)
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = p.lit
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", _knob_icon(Color.WHITE, 30))
	t.set_icon("grabber_highlight", "HSlider", _knob_icon(Color.WHITE, 34))

	t.set_stylebox("background", "ProgressBar", box(Color(1, 1, 1, 0.1), Color(0, 0, 0, 0), 0, 10, 0, 0))
	t.set_stylebox("fill", "ProgressBar", box(p.lit, Color(0, 0, 0, 0), 0, 10, 0, 0))
	t.set_color("font_color", "ProgressBar", p.ui_text)

	t.set_constant("separation", "VBoxContainer", 14)
	t.set_constant("separation", "HBoxContainer", 14)
	var sep := StyleBoxLine.new()
	sep.color = Color(1, 1, 1, 0.07)
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	var bar := box(Color(1, 1, 1, 0.18), Color(0, 0, 0, 0), 0, 6, 0, 0)
	t.set_stylebox("grabber", "VScrollBar", bar)
	t.set_stylebox("grabber_highlight", "VScrollBar", bar)
	t.set_stylebox("grabber_pressed", "VScrollBar", bar)
	t.set_stylebox("scroll", "VScrollBar", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 6, 3, 0))
	return t


# --- Procedural icons (crisp at any density, no image assets) ----------------

static func _image(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img


## Signed-distance rasteriser for a rounded rectangle / circle.
static func _paint_round(img: Image, rect: Rect2, radius: float, col: Color) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var px := Vector2(x + 0.5, y + 0.5)
			var c := rect.get_center()
			var half := rect.size * 0.5 - Vector2(radius, radius)
			var q := (px - c).abs() - half
			var dist := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - radius
			var a := clampf(0.5 - dist, 0.0, 1.0)
			if a <= 0.0:
				continue
			var under := img.get_pixel(x, y)
			var out := under.blend(Color(col, col.a * a))
			img.set_pixel(x, y, out)


static func _switch_icon(on: bool, p: Palette) -> Texture2D:
	var key := "switch_%s_%s" % [str(on), p.lit.to_html()]
	if _icons.has(key):
		return _icons[key]
	var w := 76
	var h := 44
	var img := _image(w, h)
	_paint_round(img, Rect2(0, 0, w, h), h * 0.5, p.lit if on else Color(1, 1, 1, 0.16))
	var knob := h - 8.0
	var x := (w - knob - 4.0) if on else 4.0
	_paint_round(img, Rect2(x, 4, knob, knob), knob * 0.5, Color.WHITE)
	var tex := ImageTexture.create_from_image(img)
	_icons[key] = tex
	return tex


static func _knob_icon(col: Color, size: int) -> Texture2D:
	var key := "knob_%d" % size
	if _icons.has(key):
		return _icons[key]
	var img := _image(size, size)
	_paint_round(img, Rect2(1, 1, size - 2, size - 2), (size - 2) * 0.5, col)
	var tex := ImageTexture.create_from_image(img)
	_icons[key] = tex
	return tex


static func _dot_icon(col: Color, size: int) -> Texture2D:
	var img := _image(size, size)
	_paint_round(img, Rect2(2, 2, size - 4, size - 4), (size - 4) * 0.5, col)
	return ImageTexture.create_from_image(img)


static func _chevron_icon(p: Palette) -> Texture2D:
	var key := "chevron_%s" % p.ui_text.to_html()
	if _icons.has(key):
		return _icons[key]
	var img := _image(28, 28)
	var col := Color(p.ui_text, 0.7)
	for i in 9:
		for t in 3:
			img.set_pixel(5 + i, 10 + i + t - 1, col)
			img.set_pixel(22 - i, 10 + i + t - 1, col)
	var tex := ImageTexture.create_from_image(img)
	_icons[key] = tex
	return tex
