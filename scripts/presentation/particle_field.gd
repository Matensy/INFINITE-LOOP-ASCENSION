class_name ParticleField
extends Node2D
## Pooled, capped particle system drawn in one pass with additive blending.
## Lives inside the board canvas, so positions/sizes are in board units.

const MAX_PARTICLES := 700
const KIND_DOT := 0
const KIND_STREAK := 1

## Multiplier applied to spawn counts (effects quality / reduce motion).
var density: float = 1.0
var drag: float = 1.6

var _pos := PackedVector2Array()
var _vel := PackedVector2Array()
var _life := PackedFloat32Array()
var _max_life := PackedFloat32Array()
var _size := PackedFloat32Array()
var _color := PackedColorArray()
var _kind := PackedByteArray()
var _rng := SeededRng.new(1337)


func _ready() -> void:
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat


func count() -> int:
	return _pos.size()


func clear() -> void:
	_pos.clear()
	_vel.clear()
	_life.clear()
	_max_life.clear()
	_size.clear()
	_color.clear()
	_kind.clear()
	queue_redraw()


func spawn(at: Vector2, velocity: Vector2, life: float, size: float, color: Color, kind: int = KIND_DOT) -> void:
	if _pos.size() >= MAX_PARTICLES:
		return
	_pos.append(at)
	_vel.append(velocity)
	_life.append(life)
	_max_life.append(life)
	_size.append(size)
	_color.append(color)
	_kind.append(kind)
	set_process(true)


func burst(at: Vector2, color: Color, amount: int, speed: float, life: float, size: float) -> void:
	var n := int(ceil(amount * density))
	for i in n:
		var ang := _rng.next_float() * TAU
		var spd := speed * (0.35 + 0.65 * _rng.next_float())
		spawn(at, Vector2.from_angle(ang) * spd, life * (0.6 + 0.4 * _rng.next_float()), size * (0.6 + 0.6 * _rng.next_float()), color)


## A bright comet travelling from `from` to `to` in `duration` seconds.
func comet(from: Vector2, to: Vector2, duration: float, color: Color, size: float) -> void:
	if density <= 0.0:
		return
	var d := maxf(duration, 0.02)
	spawn(from, (to - from) / d, d, size, color, KIND_STREAK)


func _process(delta: float) -> void:
	var i := 0
	var damp := maxf(0.0, 1.0 - drag * delta)
	while i < _pos.size():
		_life[i] -= delta
		if _life[i] <= 0.0:
			_remove(i)
			continue
		_pos[i] += _vel[i] * delta
		if _kind[i] == KIND_DOT:
			_vel[i] *= damp
		i += 1
	queue_redraw()
	if _pos.is_empty():
		set_process(false)


func _remove(i: int) -> void:
	var last := _pos.size() - 1
	_pos[i] = _pos[last]
	_vel[i] = _vel[last]
	_life[i] = _life[last]
	_max_life[i] = _max_life[last]
	_size[i] = _size[last]
	_color[i] = _color[last]
	_kind[i] = _kind[last]
	_pos.resize(last)
	_vel.resize(last)
	_life.resize(last)
	_max_life.resize(last)
	_size.resize(last)
	_color.resize(last)
	_kind.resize(last)


func _draw() -> void:
	for i in _pos.size():
		var a := clampf(_life[i] / _max_life[i], 0.0, 1.0)
		var col := _color[i]
		col.a *= a
		if _kind[i] == KIND_STREAK:
			var tail := _pos[i] - _vel[i] * 0.07
			draw_line(tail, _pos[i], Color(col, col.a * 0.5), _size[i] * 2.2)
			draw_line(tail.lerp(_pos[i], 0.5), _pos[i], col, _size[i])
			draw_circle(_pos[i], _size[i] * 0.9, col)
		else:
			draw_circle(_pos[i], _size[i] * (0.4 + 0.6 * a), col)
