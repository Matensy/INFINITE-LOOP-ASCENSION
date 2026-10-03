class_name PillBackground
extends Control
## Gradient pill with a soft coloured glow, drawn behind a Button
## (show_behind_parent). Reacts to the parent's hover / pressed state.

var color_a := Color("#5ef7ff")
var color_b := Color("#a78bfa")
var radius := -1.0


func _init(a: Color = Color("#5ef7ff"), b: Color = Color("#a78bfa")) -> void:
	color_a = a
	color_b = b
	show_behind_parent = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	var btn := get_parent() as BaseButton
	if btn:
		btn.button_down.connect(queue_redraw)
		btn.button_up.connect(queue_redraw)
		btn.mouse_entered.connect(queue_redraw)
		btn.mouse_exited.connect(queue_redraw)


func _draw() -> void:
	var btn := get_parent() as BaseButton
	var pressed := btn != null and btn.is_pressed()
	var dim := btn != null and btn.disabled
	var r := size.y * 0.5 if radius < 0.0 else radius
	var rect := Rect2(Vector2.ZERO, size)
	if pressed:
		rect = rect.grow(-3.0)
	# Soft glow under the pill.
	for i in 4:
		var g := rect.grow(4.0 + i * 5.0)
		g.position.y += 6.0
		_round_rect(g, r + 4.0 + i * 5.0, Color(color_a.lerp(color_b, 0.5), (0.1 - i * 0.022) * (0.3 if dim else 1.0)), Color(0, 0, 0, 0))
	var a := color_a.lightened(0.08) if pressed else color_a
	var b := color_b.lightened(0.08) if pressed else color_b
	if dim:
		a = Color(a, 0.35)
		b = Color(b, 0.35)
	_round_rect(rect, r, a, b)
	# Top highlight.
	var hl := Rect2(rect.position + Vector2(r * 0.6, 3.0), Vector2(rect.size.x - r * 1.2, rect.size.y * 0.38))
	_round_rect(hl, hl.size.y * 0.5, Color(1, 1, 1, 0.16), Color(1, 1, 1, 0.04))


## Horizontal-gradient rounded rectangle (b transparent = solid colour a).
func _round_rect(rect: Rect2, r: float, a: Color, b: Color) -> void:
	r = minf(r, minf(rect.size.x, rect.size.y) * 0.5)
	var right := b if b.a > 0.0 or a.a == 0.0 else a
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var segs := 10
	var corners := [
		[rect.position + Vector2(rect.size.x - r, r), -PI * 0.5],
		[rect.position + Vector2(rect.size.x - r, rect.size.y - r), 0.0],
		[rect.position + Vector2(r, rect.size.y - r), PI * 0.5],
		[rect.position + Vector2(r, r), PI],
	]
	for c in corners:
		var centre: Vector2 = c[0]
		for i in segs + 1:
			var ang: float = c[1] + PI * 0.5 * float(i) / segs
			var pt := centre + Vector2.from_angle(ang) * r
			pts.append(pt)
			var t := clampf((pt.x - rect.position.x) / maxf(rect.size.x, 1.0), 0.0, 1.0)
			cols.append(a.lerp(right, t))
	draw_polygon(pts, cols)
