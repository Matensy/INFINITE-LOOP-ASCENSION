class_name Palette
extends RefCounted
## Resolved colours of a theme after accessibility adjustments. Gameplay
## readability rules (contrast, colour-blind safe cores) are applied here so
## every renderer reads the same values.

## Okabe-Ito colour-blind safe palette.
const CVD_CORES: Array[String] = ["#E69F00", "#56B4E9", "#009E73", "#F0E442", "#0072B2", "#D55E00"]

var id: String = "cyber"
var bg_top := Color("#0b1030")
var bg_bottom := Color("#03040d")
var bg_accent := Color("#1b2a7a")
var bg_style := 0
var grid := Color("#18214a")
var idle := Color("#2c3d70")
var lit := Color("#5ef7ff")
var glow := Color("#36c9ff")
var hub := Color("#e9fdff")
var warn := Color("#ff4f7a")
var particle := Color("#9ffcff")
var cores: Array[Color] = []
var ui_text := Color("#e6f0ff")
var ui_dim := Color("#7f8bb3")
var ui_accent := Color("#5ef7ff")
var panel := Color("#0d1336")
var high_contrast := false
var colorblind := false


static func from_theme(theme: Dictionary, high_contrast_mode: bool = false, colorblind_mode: bool = false) -> Palette:
	var p := Palette.new()
	p.id = str(theme.get("id", "cyber"))
	p.bg_top = ThemeCatalog.color(theme, "bg_top", p.bg_top)
	p.bg_bottom = ThemeCatalog.color(theme, "bg_bottom", p.bg_bottom)
	p.bg_accent = ThemeCatalog.color(theme, "bg_accent", p.bg_accent)
	p.bg_style = int(theme.get("bg_style", 0))
	p.grid = ThemeCatalog.color(theme, "grid", p.grid)
	p.idle = ThemeCatalog.color(theme, "idle", p.idle)
	p.lit = ThemeCatalog.color(theme, "lit", p.lit)
	p.glow = ThemeCatalog.color(theme, "glow", p.glow)
	p.hub = ThemeCatalog.color(theme, "hub", p.hub)
	p.warn = ThemeCatalog.color(theme, "warn", p.warn)
	p.particle = ThemeCatalog.color(theme, "particle", p.particle)
	p.cores = ThemeCatalog.core_colors(theme)
	p.ui_text = ThemeCatalog.color(theme, "ui_text", p.ui_text)
	p.ui_dim = ThemeCatalog.color(theme, "ui_dim", p.ui_dim)
	p.ui_accent = ThemeCatalog.color(theme, "ui_accent", p.ui_accent)
	p.panel = ThemeCatalog.color(theme, "panel", p.panel)
	p.high_contrast = high_contrast_mode
	p.colorblind = colorblind_mode
	if high_contrast_mode:
		p.idle = p.idle.lerp(Color(0.62, 0.62, 0.68), 0.55)
		p.lit = p.lit.lerp(Color.WHITE, 0.35)
		p.grid = p.grid.lerp(Color(0.5, 0.5, 0.55), 0.35)
		p.bg_top = p.bg_top.darkened(0.5)
		p.bg_bottom = Color.BLACK
		p.ui_dim = p.ui_dim.lerp(Color.WHITE, 0.4)
	if colorblind_mode:
		p.cores.clear()
		for c in CVD_CORES:
			p.cores.append(Color(c))
		p.warn = Color("#CC79A7")
	return p


func core_color(index: int) -> Color:
	if index < 0 or cores.is_empty():
		return lit
	return cores[index % cores.size()]


## Distinct accent for linked groups / portal pairs.
func group_color(index: int) -> Color:
	var base := core_color(index + 2)
	return base.lerp(hub, 0.15)
