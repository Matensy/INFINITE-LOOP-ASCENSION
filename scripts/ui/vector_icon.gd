class_name VectorIcon
extends Control
## Crisp line icons drawn in code (24x24 design grid scaled to the control),
## so the UI needs no image assets and stays sharp on every screen density.

@export var icon: String = "menu"
@export var color: Color = Color.WHITE
@export var stroke: float = 2.0


func _init(icon_name: String = "menu", icon_color: Color = Color.WHITE) -> void:
	icon = icon_name
	color = icon_color
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_icon(icon_name: String) -> void:
	icon = icon_name
	queue_redraw()


func _draw() -> void:
	var s := minf(size.x, size.y) / 24.0
	var off := (size - Vector2(24, 24) * s) * 0.5
	draw_icon(self, icon, off, s, color, stroke * s)


## Draws icon `name` on `ci` with the 24x24 grid mapped by offset + scale.
static func draw_icon(ci: CanvasItem, name: String, off: Vector2, s: float, col: Color, w: float) -> void:
	var pt := func(x: float, y: float) -> Vector2: return off + Vector2(x, y) * s
	match name:
		"menu":
			for y in [7.0, 12.0, 17.0]:
				ci.draw_line(pt.call(5.0, y), pt.call(19.0, y), col, w, true)
		"pause":
			ci.draw_line(pt.call(9.0, 6.0), pt.call(9.0, 18.0), col, w * 1.2, true)
			ci.draw_line(pt.call(15.0, 6.0), pt.call(15.0, 18.0), col, w * 1.2, true)
		"back":
			ci.draw_polyline(PackedVector2Array([pt.call(15.0, 5.0), pt.call(8.0, 12.0), pt.call(15.0, 19.0)]), col, w, true)
		"close":
			ci.draw_line(pt.call(6.0, 6.0), pt.call(18.0, 18.0), col, w, true)
			ci.draw_line(pt.call(18.0, 6.0), pt.call(6.0, 18.0), col, w, true)
		"undo":
			ci.draw_arc(pt.call(13.0, 13.0), 6.5 * s, deg_to_rad(-200.0), deg_to_rad(80.0), 24, col, w, true)
			var tip: Vector2 = pt.call(6.9, 10.8)
			ci.draw_polyline(PackedVector2Array([tip + Vector2(-0.5, -4.5) * s, tip, tip + Vector2(4.5, 0.5) * s]), col, w, true)
		"replay":
			ci.draw_arc(pt.call(12.0, 12.0), 7.0 * s, deg_to_rad(-60.0), deg_to_rad(240.0), 28, col, w, true)
			var t2: Vector2 = pt.call(15.5, 5.9)
			ci.draw_polyline(PackedVector2Array([t2 + Vector2(-4.0, -1.5) * s, t2, t2 + Vector2(-1.0, 4.0) * s]), col, w, true)
		"hint":
			ci.draw_arc(pt.call(12.0, 10.0), 5.5 * s, deg_to_rad(140.0), deg_to_rad(400.0), 24, col, w, true)
			ci.draw_line(pt.call(9.5, 15.5), pt.call(9.5, 17.0), col, w, true)
			ci.draw_line(pt.call(14.5, 15.5), pt.call(14.5, 17.0), col, w, true)
			ci.draw_line(pt.call(9.5, 17.5), pt.call(14.5, 17.5), col, w, true)
			ci.draw_line(pt.call(10.5, 20.0), pt.call(13.5, 20.0), col, w, true)
		"settings":
			ci.draw_arc(pt.call(12.0, 12.0), 3.2 * s, 0.0, TAU, 20, col, w, true)
			ci.draw_arc(pt.call(12.0, 12.0), 6.8 * s, 0.0, TAU, 32, col, w, true)
			for k in 8:
				var a := TAU * k / 8.0
				ci.draw_line(pt.call(12.0, 12.0) + Vector2.from_angle(a) * 6.8 * s, pt.call(12.0, 12.0) + Vector2.from_angle(a) * 9.2 * s, col, w * 1.3, true)
		"user":
			ci.draw_arc(pt.call(12.0, 8.5), 3.8 * s, 0.0, TAU, 24, col, w, true)
			ci.draw_arc(pt.call(12.0, 21.5), 7.5 * s, deg_to_rad(200.0), deg_to_rad(340.0), 24, col, w, true)
		"calendar":
			ci.draw_rect(Rect2(pt.call(4.5, 6.0), Vector2(15, 13.5) * s), col, false, w)
			ci.draw_line(pt.call(4.5, 10.5), pt.call(19.5, 10.5), col, w, true)
			ci.draw_line(pt.call(8.5, 4.0), pt.call(8.5, 7.5), col, w, true)
			ci.draw_line(pt.call(15.5, 4.0), pt.call(15.5, 7.5), col, w, true)
			ci.draw_circle(pt.call(12.0, 15.0), 1.4 * s, col)
		"infinity":
			var pts := PackedVector2Array()
			for i in 49:
				var t := TAU * i / 48.0
				var d := 1.0 + sin(t) * sin(t)
				pts.append(pt.call(12.0 + 8.0 * cos(t) / d, 12.0 + 8.0 * sin(t) * cos(t) / d))
			ci.draw_polyline(pts, col, w, true)
		"bolt":
			ci.draw_polyline(PackedVector2Array([pt.call(13.5, 3.5), pt.call(6.5, 13.5), pt.call(11.5, 13.5),
					pt.call(10.0, 20.5), pt.call(17.5, 10.0), pt.call(12.5, 10.0), pt.call(13.5, 3.5)]), col, w, true)
		"hash":
			ci.draw_line(pt.call(9.5, 4.5), pt.call(8.0, 19.5), col, w, true)
			ci.draw_line(pt.call(16.0, 4.5), pt.call(14.5, 19.5), col, w, true)
			ci.draw_line(pt.call(5.0, 9.5), pt.call(19.5, 9.5), col, w, true)
			ci.draw_line(pt.call(4.5, 14.5), pt.call(19.0, 14.5), col, w, true)
		"play":
			ci.draw_colored_polygon(PackedVector2Array([pt.call(8.0, 5.0), pt.call(19.0, 12.0), pt.call(8.0, 19.0)]), col)
		"share":
			var a: Vector2 = pt.call(17.0, 6.0)
			var b: Vector2 = pt.call(7.0, 12.0)
			var c: Vector2 = pt.call(17.0, 18.0)
			ci.draw_line(a, b, col, w, true)
			ci.draw_line(b, c, col, w, true)
			for q in [a, b, c]:
				ci.draw_circle(q, 2.6 * s, col)
		"star", "star_fill":
			var star := PackedVector2Array()
			for k in 10:
				var r := 8.5 if k % 2 == 0 else 3.8
				star.append(pt.call(12.0, 12.5) + Vector2.from_angle(-PI / 2.0 + k * PI / 5.0) * r * s)
			if name == "star_fill":
				ci.draw_colored_polygon(star, col)
			else:
				star.append(star[0])
				ci.draw_polyline(star, col, w, true)
		"trophy":
			ci.draw_arc(pt.call(12.0, 7.0), 5.5 * s, 0.0, PI, 16, col, w, true)
			ci.draw_line(pt.call(6.5, 4.5), pt.call(6.5, 7.0), col, w, true)
			ci.draw_line(pt.call(17.5, 4.5), pt.call(17.5, 7.0), col, w, true)
			ci.draw_line(pt.call(6.5, 4.5), pt.call(17.5, 4.5), col, w, true)
			ci.draw_line(pt.call(12.0, 12.5), pt.call(12.0, 17.0), col, w, true)
			ci.draw_line(pt.call(8.0, 19.5), pt.call(16.0, 19.5), col, w, true)
		"check":
			ci.draw_polyline(PackedVector2Array([pt.call(5.0, 12.5), pt.call(10.0, 17.5), pt.call(19.0, 7.0)]), col, w * 1.2, true)
		"lock":
			ci.draw_rect(Rect2(pt.call(6.0, 11.0), Vector2(12, 9) * s), col, false, w)
			ci.draw_arc(pt.call(12.0, 11.0), 4.0 * s, PI, TAU, 16, col, w, true)
		"bug":
			ci.draw_arc(pt.call(12.0, 13.5), 5.0 * s, 0.0, TAU, 24, col, w, true)
			ci.draw_line(pt.call(12.0, 8.5), pt.call(12.0, 18.5), col, w, true)
			for y in [11.0, 14.0, 17.0]:
				ci.draw_line(pt.call(4.5, y), pt.call(7.0, y), col, w, true)
				ci.draw_line(pt.call(17.0, y), pt.call(19.5, y), col, w, true)
		"grid":
			for gx in 3:
				for gy in 3:
					ci.draw_circle(pt.call(6.0 + gx * 6.0, 6.0 + gy * 6.0), 1.6 * s, col)
		_:
			ci.draw_arc(pt.call(12.0, 12.0), 7.0 * s, 0.0, TAU, 24, col, w, true)
