extends Node
## Autoload "Haptics": short vibration patterns, respecting settings.

enum Kind { TAP, CONNECT, IMPORTANT, DENIED, SOLVE, BOSS, UI }

## [duration_ms, amplitude] pairs; a 0-amplitude entry is a pause.
const PATTERNS := {
	Kind.TAP: [[8, 0.25]],
	Kind.CONNECT: [[14, 0.45]],
	Kind.IMPORTANT: [[26, 0.7]],
	Kind.DENIED: [[30, 0.55], [40, 0.0], [30, 0.55]],
	Kind.SOLVE: [[18, 0.5], [60, 0.0], [28, 0.7], [60, 0.0], [55, 1.0]],
	Kind.BOSS: [[30, 0.6], [45, 0.0], [30, 0.7], [45, 0.0], [30, 0.85], [45, 0.0], [140, 1.0]],
	Kind.UI: [[6, 0.2]],
}

var _supported := false


func _ready() -> void:
	_supported = OS.has_feature("mobile")


func pulse(kind: int) -> void:
	if not _supported or not _enabled():
		return
	var strength := float(_save_setting("haptic_strength", 1.0))
	var pattern: Array = PATTERNS.get(kind, [])
	for step in pattern:
		var ms: int = step[0]
		var amp: float = step[1]
		if amp > 0.0:
			Input.vibrate_handheld(ms, clampf(amp * strength, 0.05, 1.0))
		await get_tree().create_timer(ms / 1000.0).timeout


func _enabled() -> bool:
	return bool(_save_setting("haptics", true))


func _save_setting(key: String, default: Variant) -> Variant:
	var save := get_node_or_null("/root/Save")
	return save.setting(key, default) if save else default
