extends SceneTree
## Rasterises the SVG icons into the PNG launcher icons Android expects.
##   godot --headless --path . --script res://tools/make_icons.gd

const JOBS := [
	["res://icon.svg", "res://assets/art/icon_192.png", 192],
	["res://icon.svg", "res://assets/art/icon_512.png", 512],
	["res://assets/art/icon_foreground.svg", "res://assets/art/icon_foreground_432.png", 432],
	["res://assets/art/icon_background.svg", "res://assets/art/icon_background_432.png", 432],
]


func _init() -> void:
	for job in JOBS:
		var text := FileAccess.get_file_as_string(job[0])
		var img := Image.new()
		var probe := Image.new()
		probe.load_svg_from_string(text, 1.0)
		var scale := float(job[2]) / float(maxi(1, probe.get_width()))
		if img.load_svg_from_string(text, scale) != OK:
			push_error("cannot rasterise " + job[0])
			continue
		img.resize(job[2], job[2], Image.INTERPOLATE_LANCZOS)
		img.save_png(ProjectSettings.globalize_path(job[1]))
		print("wrote ", job[1])
	quit()
