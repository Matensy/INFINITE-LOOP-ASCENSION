class_name BoardGestures
extends RefCounted
## Gesture recogniser for BoardView: tap, double tap, long press, drag to
## pan, pinch to zoom, two-finger tap, right click and mouse wheel. It only
## tracks pointer state; the view supplies the camera and receives intents
## through its signals.

const LONG_PRESS := 0.38
const DOUBLE_TAP := 0.3
const DRAG_THRESHOLD := 14.0
const TWO_FINGER_TAP := 0.3

var view: BoardView

var _touches: Dictionary = {}
var _press_active := false
var _press_pos := Vector2.ZERO
var _press_time := 0.0
var _press_cell := -1
var _long_fired := false
var _dragging := false
var _pinch_dist := 0.0
var _pinch_zoom := 1.0
var _pinch_mid := Vector2.ZERO
var _two_finger_start := -1.0
var _two_finger_moved := false
var _last_tap_time := -10.0
var _last_tap_cell := -2
var _mouse_down := false


func _init(board: BoardView) -> void:
	view = board


static func _now() -> float:
	return Time.get_ticks_usec() / 1000000.0


## Returns true when the event was consumed.
func handle(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		_on_touch(event)
		return true
	if event is InputEventScreenDrag:
		_on_drag(event)
		return true
	if event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		_on_mouse_button(event)
		return true
	if event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		if _mouse_down:
			_drag_single(event.position, event.relative)
		return true
	return false


## Per-frame check for the long press. Returns true while a press is held.
func update() -> bool:
	if not _press_active or not view.interactive or _long_fired or _dragging or _touches.size() > 1:
		return false
	if _now() - _press_time >= LONG_PRESS and _press_cell >= 0:
		_long_fired = true
		view.cell_tapped.emit(_press_cell, -1)
	return true


func _on_touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		_touches[e.index] = e.position
		if _touches.size() == 1:
			_begin_press(e.position)
		elif _touches.size() == 2:
			_press_active = false
			var pts: Array = _touches.values()
			_pinch_dist = maxf(1.0, (pts[0] as Vector2).distance_to(pts[1]))
			_pinch_zoom = view.zoom
			_pinch_mid = ((pts[0] as Vector2) + (pts[1] as Vector2)) * 0.5
			_two_finger_start = _now()
			_two_finger_moved = false
	else:
		var was_two := _touches.size() == 2
		_touches.erase(e.index)
		if was_two:
			if _two_finger_start >= 0.0 and not _two_finger_moved and _now() - _two_finger_start < TWO_FINGER_TAP:
				view.gesture_used.emit("two_finger")
				view.two_finger_tapped.emit()
			_two_finger_start = -1.0
			_press_active = false
			_dragging = true  # remaining finger must not tap
		elif _touches.is_empty():
			_end_press(e.position)


func _on_drag(e: InputEventScreenDrag) -> void:
	_touches[e.index] = e.position
	if _touches.size() >= 2:
		var pts: Array = _touches.values()
		var a: Vector2 = pts[0]
		var b: Vector2 = pts[1]
		var dist := maxf(1.0, a.distance_to(b))
		var mid := (a + b) * 0.5
		if absf(dist - _pinch_dist) > DRAG_THRESHOLD or mid.distance_to(_pinch_mid) > DRAG_THRESHOLD:
			_two_finger_moved = true
		if _two_finger_moved:
			var new_zoom := clampf(_pinch_zoom * dist / _pinch_dist, 1.0, view.max_zoom())
			var ratio := new_zoom / maxf(view.zoom, 0.001)
			var centre := view.size * 0.5
			var pan := (view.pan + centre - mid) * ratio - centre + mid
			pan += mid - _pinch_mid
			_pinch_mid = mid
			view.set_camera(new_zoom, pan)
			view.gesture_used.emit("pinch")
	elif _touches.size() == 1:
		_drag_single(e.position, e.relative)


func _drag_single(pos: Vector2, relative: Vector2) -> void:
	if not _dragging and pos.distance_to(_press_pos) > DRAG_THRESHOLD:
		_dragging = true
		_press_active = false
	if _dragging and view.zoom > 1.001:
		view.set_camera(view.zoom, view.pan + relative)
		view.gesture_used.emit("drag")


func _on_mouse_button(e: InputEventMouseButton) -> void:
	match e.button_index:
		MOUSE_BUTTON_LEFT:
			if e.pressed:
				_mouse_down = true
				_begin_press(e.position)
			else:
				_mouse_down = false
				_end_press(e.position)
		MOUSE_BUTTON_RIGHT:
			if e.pressed and view.interactive:
				var c := view.cell_at_local(e.position)
				if c >= 0:
					view.cell_tapped.emit(c, -1)
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if e.pressed:
				var factor := 1.12 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12
				view.zoom_at(e.position, view.zoom * factor)


func _begin_press(pos: Vector2) -> void:
	_press_active = true
	_press_pos = pos
	_press_time = _now()
	_press_cell = view.cell_at_local(pos)
	_long_fired = false
	_dragging = false
	if _press_cell >= 0 and view.puzzle.link_of[_press_cell] >= 0:
		view.set_link_focus(view.puzzle.link_of[_press_cell])
	view.set_process(true)


func _end_press(pos: Vector2) -> void:
	var was_active := _press_active
	_press_active = false
	view.set_link_focus(-1)
	if not was_active or _dragging or _long_fired or not view.interactive:
		_dragging = false
		return
	var cell := view.cell_at_local(pos)
	if cell != _press_cell:
		return
	var now := _now()
	var double := now - _last_tap_time < DOUBLE_TAP and cell == _last_tap_cell
	_last_tap_time = -10.0 if double else now
	_last_tap_cell = cell
	if cell < 0:
		if double:
			view.empty_double_tapped.emit()
		return
	view.ripple(cell)
	if double:
		view.cell_double_tapped.emit(cell)
	else:
		view.cell_tapped.emit(cell, 1)
