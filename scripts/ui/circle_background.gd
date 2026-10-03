class_name CircleBackground
extends Control
## Anti-aliased frosted disc drawn behind a round icon Button
## (show_behind_parent). StyleBoxFlat with radius = size / 2 shows a seam
## where the four corner arcs meet, so round buttons draw their own disc.

var fill := Color(1, 1, 1, 0.08)
var border := Color(1, 1, 1, 0.1)


func _init(fill_color: Color = Color(1, 1, 1, 0.08), border_color: Color = Color(1, 1, 1, 0.1)) -> void:
	fill = fill_color
	border = border_color
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
	var boost := 1.0
	if btn:
		if btn.disabled:
			boost = 0.4
		elif btn.is_pressed():
			boost = 2.4
		elif btn.is_hovered():
			boost = 1.6
	var centre := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	draw_circle(centre, r - 0.5, Color(fill, minf(fill.a * boost, 1.0)), true, -1.0, true)
	draw_arc(centre, r - 1.0, 0.0, TAU, 72, Color(border, minf(border.a * boost, 1.0)), 1.5, true)
