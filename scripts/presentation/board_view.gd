class_name BoardView
extends Control
## Renders a puzzle and converts touch / mouse gestures into intents.
##
## Architecture (spec §48-49): puzzle *data* is drawn by a few batched canvas
## layers instead of one Node per tile:
##   cells layer   - static cell backgrounds (one triangle batch)
##   tiles layer   - every resting tile, redrawn only when the board changes
##   fx layer      - rotating tiles, cores, portals, hints, victory glow
##   particles     - pooled additive particles
## All geometry is in board units; one Node2D transform maps it to pixels
## (zoom / pan / camera pulse).

signal cell_tapped(cell: int, steps: int)
signal cell_double_tapped(cell: int)
signal empty_double_tapped
signal two_finger_tapped
signal gesture_used(kind: String)
signal victory_finished

const LONG_PRESS := 0.38
const DOUBLE_TAP := 0.3
const DRAG_THRESHOLD := 14.0
const MIN_CELL_PX := 34.0
const MAX_CELL_PX := 150.0
const SPRING_K := 340.0
const SPRING_DAMP := 24.0
const PADDING := 18.0

## Cross-section profiles for textured arm quads: a crisp anti-aliased core
## and a soft gaussian glow, both batched into single triangle arrays.
static var _core_tex: ImageTexture
static var _glow_tex: ImageTexture

var puzzle: Puzzle
var state: BoardState
var session: GameSession
var palette: Palette = Palette.new()
var interactive: bool = true
## Menu decoration: shows the solution and loops the energy wave.
var attract: bool = false
var animation_speed: float = 1.0
var reduce_motion: bool = false
var high_effects: bool = true

var zoom: float = 1.0
var pan: Vector2 = Vector2.ZERO

var particles: ParticleField

var _canvas: Node2D
var _cells_layer: Layer
var _tiles_layer: Layer
var _fx_layer: Layer

var _fit := 1.0
var _unit := 1.0
var _pending_auto_zoom := false

var _time := 0.0
var _anim_angle := PackedFloat32Array()
var _anim_vel := PackedFloat32Array()
var _animating: Dictionary = {}
var _shake: Dictionary = {}
var _matched := PackedInt32Array()
var _power := PackedInt32Array()
var _dark_good := PackedInt32Array()
var _highlight := PackedInt32Array()
var _highlight_t := 0.0
var _link_focus := -1

var _victory_t := -1.0
var _victory_start := PackedFloat32Array()
var _victory_end := 0.0
var _victory_fired := PackedByteArray()
var _victory_done := false
var _pulse_t := -1.0
var _attract_timer := 0.0

# Gesture state.
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
var _pinch_pan := Vector2.ZERO
var _two_finger_start := -1.0
var _two_finger_moved := false
var _last_tap_time := -10.0
var _last_tap_cell := -2
var _mouse_down := false


## Canvas layer whose drawing is delegated to the owning BoardView.
class Layer:
	extends Node2D
	var painter: Callable

	func _draw() -> void:
		if painter.is_valid():
			painter.call(self)


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas = Node2D.new()
	add_child(_canvas)
	_cells_layer = Layer.new()
	_cells_layer.painter = _paint_cells
	_tiles_layer = Layer.new()
	_tiles_layer.painter = _paint_tiles
	_fx_layer = Layer.new()
	_fx_layer.painter = _paint_fx
	particles = ParticleField.new()
	_canvas.add_child(_cells_layer)
	_canvas.add_child(_tiles_layer)
	_canvas.add_child(_fx_layer)
	_canvas.add_child(particles)
	resized.connect(_layout)
	if _core_tex == null:
		_core_tex = _profile_texture(true)
		_glow_tex = _profile_texture(false)


static func _profile_texture(sharp: bool) -> ImageTexture:
	var w := 64
	var img := Image.create(w, 4, false, Image.FORMAT_RGBA8)
	for x in w:
		var u := ((x + 0.5) / w) * 2.0 - 1.0
		var a := clampf((1.0 - absf(u)) * 5.0, 0.0, 1.0) if sharp else exp(-u * u * 4.0) * (1.0 - absf(u))
		for y in 4:
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


# --- Setup ------------------------------------------------------------------

func show_puzzle(p: Puzzle, board_state: BoardState, play_session: GameSession = null) -> void:
	puzzle = p
	state = board_state
	session = play_session
	var n := p.cell_count()
	_anim_angle.resize(n)
	_anim_angle.fill(0.0)
	_anim_vel.resize(n)
	_anim_vel.fill(0.0)
	_animating.clear()
	_shake.clear()
	_highlight = PackedInt32Array()
	_victory_t = -1.0
	_victory_done = false
	_pulse_t = -1.0
	_link_focus = -1
	particles.clear()
	_unit = p.topology.apothem() * 2.0
	zoom = 1.0
	pan = Vector2.ZERO
	_pending_auto_zoom = true
	_layout()
	refresh()
	_cells_layer.queue_redraw()


func set_palette(p: Palette) -> void:
	palette = p
	_cells_layer.queue_redraw()
	_tiles_layer.queue_redraw()
	_fx_layer.queue_redraw()


func set_effects(speed: float, reduced: bool, high: bool) -> void:
	animation_speed = clampf(speed, 0.25, 3.0)
	reduce_motion = reduced
	high_effects = high
	particles.density = (1.0 if high else 0.45) * (0.4 if reduced else 1.0)


## Applies the accessibility / effects settings dictionary from the save.
func apply_user_settings(settings: Dictionary) -> void:
	set_effects(float(settings.get("animation_speed", 1.0)), bool(settings.get("reduce_motion", false)),
			str(settings.get("effects", "high")) == "high")


## Recomputes connection / power state and redraws resting tiles.
func refresh() -> void:
	if puzzle == null:
		return
	var masks := state.masks()
	_matched = Connectivity.matched_mask(puzzle, masks)
	if GameMode.uses_cores(puzzle.mode):
		_power = Connectivity.power(puzzle, masks)
	else:
		_power = PackedInt32Array()
	if puzzle.mode == GameMode.DARK:
		_compute_dark(masks)
	_tiles_layer.queue_redraw()
	_fx_layer.queue_redraw()


func _compute_dark(masks: PackedInt32Array) -> void:
	var n := puzzle.cell_count()
	var dc := puzzle.dir_count()
	_dark_good.resize(n)
	for c in n:
		var m := masks[c]
		var good := 0
		for d in dc:
			if (m >> d) & 1 == 0:
				continue
			var other := puzzle.nbr[c * dc + d]
			if other >= 0 and (masks[other] >> puzzle.topology.opposite(d)) & 1 == 0:
				good |= 1 << d
		_dark_good[c] = good


# --- Camera -----------------------------------------------------------------

func _layout() -> void:
	if puzzle == null or size.x <= 1.0 or size.y <= 1.0:
		return
	var bs := puzzle.topology.board_size()
	var avail := size - Vector2(PADDING, PADDING) * 2.0
	_fit = minf(avail.x / bs.x, avail.y / bs.y)
	if _pending_auto_zoom:
		_pending_auto_zoom = false
		_auto_zoom()
	_clamp_camera()
	_apply_transform()


func _auto_zoom() -> void:
	var cell_px := _fit * _unit
	if cell_px > 0.0 and cell_px < MIN_CELL_PX:
		zoom = minf(MIN_CELL_PX / cell_px, _max_zoom())
	_clamp_camera()
	_apply_transform()


func _max_zoom() -> float:
	return maxf(1.0, MAX_CELL_PX / maxf(_fit * _unit, 1.0))


func reset_view() -> void:
	zoom = 1.0
	pan = Vector2.ZERO
	_apply_transform()


func _clamp_camera() -> void:
	zoom = clampf(zoom, 1.0, _max_zoom())
	if puzzle == null:
		return
	var board_px := puzzle.topology.board_size() * _fit * zoom
	var slack := ((board_px - size) * 0.5).max(Vector2.ZERO) + Vector2(60, 60)
	pan = pan.clamp(-slack, slack)


func _scale() -> float:
	var s := _fit * zoom
	if _pulse_t >= 0.0 and not reduce_motion:
		s *= 1.0 + 0.045 * sin(PI * clampf(_pulse_t / 0.4, 0.0, 1.0))
	return s


func _apply_transform() -> void:
	if puzzle == null:
		return
	var s := _scale()
	var bs := puzzle.topology.board_size()
	_canvas.scale = Vector2(s, s)
	_canvas.position = size * 0.5 - bs * 0.5 * s + pan


func local_to_board(p: Vector2) -> Vector2:
	return _canvas.transform.affine_inverse() * p


func board_to_local(p: Vector2) -> Vector2:
	return _canvas.transform * p


func cell_at_local(p: Vector2) -> int:
	if puzzle == null:
		return -1
	var c := puzzle.topology.cell_at(local_to_board(p))
	if c < 0 or puzzle.active[c] == 0:
		return -1
	return c


func cell_screen_position(cell: int) -> Vector2:
	return get_global_transform() * board_to_local(puzzle.topology.cell_center(cell))


# --- Animation API ------------------------------------------------------------

## Called after the model rotated `cells` by `steps`: animate from the old
## orientation with a springy settle.
func animate_rotation(cells: PackedInt32Array, steps: int) -> void:
	var step := puzzle.topology.step_angle()
	for c in cells:
		_anim_angle[c] -= steps * step
		_anim_vel[c] = 0.0
		_animating[c] = true
		if high_effects:
			var center := puzzle.topology.cell_center(c)
			particles.burst(center, Color(palette.glow, 0.7), 3, 1.6 * _unit, 0.28, 0.05 * _unit)
	refresh()
	set_process(true)


## Feedback for refused taps (locked / pinned tiles).
func shake(cell: int) -> void:
	_shake[cell] = 0.3
	set_process(true)


## Sparks on edges that just became connected around `cells`.
func spark_connections(cells: PackedInt32Array) -> void:
	if puzzle == null:
		return
	var dc := puzzle.dir_count()
	for c in cells:
		var m := _matched[c]
		for d in dc:
			if (m >> d) & 1 == 0:
				continue
			var at := puzzle.topology.cell_center(c) + puzzle.topology.dir_vector(d) * puzzle.topology.apothem()
			particles.burst(at, Color(_arm_color(c, d, true), 0.9), 5, 2.4 * _unit, 0.35, 0.05 * _unit)


func set_highlight(cells: PackedInt32Array) -> void:
	_highlight = cells
	_highlight_t = 0.0
	set_process(true)


func clear_highlight() -> void:
	_highlight = PackedInt32Array()
	_fx_layer.queue_redraw()


## Plays the solve sequence: energy propagates from `origins` through the
## network, every tile lights up, particles ride the connections, then a
## camera pulse. Emits victory_finished when done (about 1.2 - 2.4 s).
func play_victory(origins: PackedInt32Array) -> void:
	var masks := state.masks()
	var starts := origins
	if starts.is_empty():
		starts = PackedInt32Array([_center_cell()])
	var dist := Connectivity.distances(puzzle, masks, starts)
	var topo := puzzle.topology
	var origin_pos := topo.cell_center(starts[0])
	var max_d := 1.0
	var n := puzzle.cell_count()
	var fdist := PackedFloat32Array()
	fdist.resize(n)
	for c in n:
		if puzzle.active[c] == 0:
			fdist[c] = -1.0
			continue
		if dist[c] >= 0:
			fdist[c] = float(dist[c])
		else:
			fdist[c] = topo.cell_center(c).distance_to(origin_pos) / _unit + 0.5
		max_d = maxf(max_d, fdist[c])
	var speed := animation_speed * (1.8 if reduce_motion else 1.0)
	var step := clampf(1.15 / max_d, 0.018, 0.09) / speed
	_victory_start.resize(n)
	_victory_fired.resize(n)
	_victory_fired.fill(0)
	for c in n:
		_victory_start[c] = fdist[c] * step if fdist[c] >= 0.0 else -1.0
	_victory_end = max_d * step + 0.45 / speed
	_victory_t = 0.0
	_victory_done = false
	set_process(true)


func _center_cell() -> int:
	var centre := puzzle.topology.board_size() * 0.5
	var best := 0
	var best_d := INF
	for c in puzzle.cell_count():
		if puzzle.active[c] == 1 and state.mask(c) != 0:
			var d := puzzle.topology.cell_center(c).distance_squared_to(centre)
			if d < best_d:
				best_d = d
				best = c
	return best


func is_victory_playing() -> bool:
	return _victory_t >= 0.0 and not _victory_done


# --- Frame update -------------------------------------------------------------

func _process(delta: float) -> void:
	if puzzle == null:
		return
	_time += delta
	var busy := false
	var settled: Array = []
	var k := SPRING_K * animation_speed * animation_speed
	var damp := SPRING_DAMP * animation_speed
	if reduce_motion:
		k *= 2.5
		damp *= 1.6
	for c in _animating.keys():
		var a := _anim_angle[c]
		var v := _anim_vel[c]
		v += (-k * a - damp * v) * delta
		a += v * delta
		if absf(a) < 0.002 and absf(v) < 0.05:
			a = 0.0
			v = 0.0
			settled.append(c)
		_anim_angle[c] = a
		_anim_vel[c] = v
	for c in settled:
		_animating.erase(c)
	if not settled.is_empty():
		_tiles_layer.queue_redraw()
	busy = busy or not _animating.is_empty()

	for c in _shake.keys():
		_shake[c] -= delta
		if _shake[c] <= 0.0:
			_shake.erase(c)
	busy = busy or not _shake.is_empty()

	if not _highlight.is_empty():
		_highlight_t += delta
		busy = true

	if _victory_t >= 0.0 and not _victory_done:
		_victory_t += delta
		_victory_particles()
		_tiles_layer.queue_redraw()
		if _victory_t >= _victory_end - 0.4 / animation_speed and _pulse_t < 0.0:
			_pulse_t = 0.0
			_final_burst()
		if _victory_t >= _victory_end:
			_victory_done = true
			_tiles_layer.queue_redraw()
			victory_finished.emit()
		busy = true

	if _pulse_t >= 0.0:
		_pulse_t += delta
		if _pulse_t > 0.4:
			_pulse_t = -1.0
		_apply_transform()
		busy = true

	if _press_active and interactive and not _long_fired and not _dragging and _touches.size() <= 1:
		if _time - _press_time >= LONG_PRESS and _press_cell >= 0:
			_long_fired = true
			cell_tapped.emit(_press_cell, -1)
		busy = true

	if attract:
		_attract_timer -= delta
		if _attract_timer <= 0.0:
			_attract_timer = 5.5
			play_victory(puzzle.cores if not puzzle.cores.is_empty() else PackedInt32Array([_random_tile()]))
		busy = true

	# Cores and portals breathe continuously.
	if not puzzle.cores.is_empty() or puzzle.portal_count() > 0 or busy:
		_fx_layer.queue_redraw()
	if not busy and puzzle.cores.is_empty() and puzzle.portal_count() == 0 and particles.count() == 0:
		set_process(false)


func _random_tile() -> int:
	var cells := PackedInt32Array()
	for c in puzzle.cell_count():
		if puzzle.active[c] == 1 and state.mask(c) != 0:
			cells.append(c)
	if cells.is_empty():
		return 0
	return cells[int(_time * 1000.0) % cells.size()]


func _victory_particles() -> void:
	var topo := puzzle.topology
	var dc := puzzle.dir_count()
	var masks := state.masks()
	for c in puzzle.cell_count():
		if _victory_fired[c] == 1 or _victory_start[c] < 0.0 or _victory_t < _victory_start[c]:
			continue
		_victory_fired[c] = 1
		var m := masks[c]
		if m == 0:
			continue
		var col := _lit_color(c)
		var centre := topo.cell_center(c)
		for d in dc:
			if (m >> d) & 1 == 0:
				continue
			var other := puzzle.nbr[c * dc + d]
			if other >= 0 and _victory_start[other] > _victory_start[c]:
				var dur := maxf(0.05, _victory_start[other] - _victory_start[c])
				particles.comet(centre, topo.cell_center(other), dur, col, 0.045 * _unit)
		if high_effects and (c % 3 == 0):
			particles.burst(centre, Color(col, 0.6), 2, 1.2 * _unit, 0.45, 0.04 * _unit)


func _final_burst() -> void:
	var topo := puzzle.topology
	var origins := puzzle.cores if not puzzle.cores.is_empty() else PackedInt32Array([_center_cell()])
	for c in origins:
		particles.burst(topo.cell_center(c), palette.hub, 26, 7.0 * _unit, 0.9, 0.07 * _unit)
	var bs := topo.board_size()
	for i in 18:
		var at := Vector2(fmod(i * 7.31, 1.0) * bs.x, fmod(i * 3.77, 1.0) * bs.y)
		particles.burst(at, Color(palette.lit, 0.8), 2, 3.0 * _unit, 0.7, 0.05 * _unit)


# --- Colours ------------------------------------------------------------------

## Brightness 0..1 of a tile during the victory wave (1 after it).
func _victory_level(c: int) -> float:
	if _victory_done:
		return 1.0
	if _victory_t < 0.0 or _victory_start.size() <= c or _victory_start[c] < 0.0:
		return 0.0
	return clampf((_victory_t - _victory_start[c]) / 0.22, 0.0, 1.0)


## Unconnected arms: theme idle colour lifted slightly for legibility.
func _idle() -> Color:
	return palette.idle.lerp(palette.ui_dim, 0.35)


func _lit_color(c: int) -> Color:
	if GameMode.uses_cores(puzzle.mode) and _power.size() > c and _power[c] >= 0:
		return palette.core_color(_power[c])
	return palette.lit


func _arm_color(c: int, d: int, matched: bool) -> Color:
	var base: Color
	match puzzle.mode:
		GameMode.DARK:
			base = palette.lit if (_dark_good.size() > c and (_dark_good[c] >> d) & 1 == 1) else palette.warn
		GameMode.CORE, GameMode.MULTI:
			var owner := _power[c] if _power.size() > c else -1
			if owner == Connectivity.CONFLICT:
				base = palette.warn
			elif owner >= 0:
				base = palette.core_color(owner) if matched else palette.core_color(owner).lerp(_idle(), 0.55)
			else:
				base = _idle().lerp(palette.lit, 0.25) if matched else _idle()
		_:
			base = palette.lit if matched else _idle()
	var v := _victory_level(c)
	if v > 0.0:
		base = base.lerp(_lit_color(c).lerp(Color.WHITE, 0.25), v * 0.6)
	return base


# --- Painting -----------------------------------------------------------------

func _paint_cells(ci: CanvasItem) -> void:
	if puzzle == null:
		return
	var topo := puzzle.topology
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var bs := topo.board_size()
	for c in puzzle.cell_count():
		if puzzle.active[c] == 0:
			continue
		var centre := topo.cell_center(c)
		var poly := topo.cell_polygon(c)
		var base := points.size()
		var shade := 1.0 - 0.35 * (centre.y / bs.y)
		var col := Color(palette.grid, 0.55 * shade)
		points.append(centre)
		colors.append(Color(col, col.a * 0.6))
		for v in poly:
			points.append(centre + (v - centre) * 0.93)
			colors.append(col)
		var count := poly.size()
		for i in count:
			indices.append(base)
			indices.append(base + 1 + i)
			indices.append(base + 1 + (i + 1) % count)
	if not points.is_empty():
		RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), indices, points, colors)


func _paint_tiles(ci: CanvasItem) -> void:
	if puzzle == null:
		return
	var segs := {}
	var hubs: Array = []
	var ends: Array = []
	var marks := PackedVector2Array()
	var pins := PackedVector2Array()
	for c in puzzle.cell_count():
		if puzzle.active[c] == 0 or _animating.has(c) or _shake.has(c):
			continue
		_collect_tile(c, 0.0, segs, hubs, ends)
		if puzzle.locked[c] == 1:
			_collect_lock_marks(c, marks)
		if session and session.pinned.size() > c and session.pinned[c] == 1:
			pins.append(puzzle.topology.cell_center(c))
	_draw_collected(ci, segs, hubs, ends)
	if not marks.is_empty():
		ci.draw_multiline(marks, Color(palette.hub, 0.5), 0.035 * _unit)
	for p in pins:
		var off := Vector2(-0.3, -0.3) * _unit
		ci.draw_circle(p + off, 0.07 * _unit, Color(palette.ui_accent, 0.9))
	_draw_link_badges(ci)


func _collect_tile(c: int, angle: float, segs: Dictionary, hubs: Array, ends: Array) -> void:
	var topo := puzzle.topology
	var m := state.mask(c)
	if m == 0:
		return
	var centre := topo.cell_center(c)
	var apo := topo.apothem()
	var dc := topo.dir_count
	var degree := 0
	var hub_col := Color(0, 0, 0, 0)
	for d in dc:
		if (m >> d) & 1 == 0:
			continue
		degree += 1
		var matched := (_matched[c] >> d) & 1 == 1 and angle == 0.0
		var dark_ok := puzzle.mode == GameMode.DARK
		var col := _arm_color(c, d, matched)
		var length := apo if (matched or dark_ok) else apo * 0.8
		if dark_ok:
			length = apo * 0.86
		var dir := topo.dir_vector(d).rotated(angle)
		var tip := centre + dir * length
		if not segs.has(col):
			segs[col] = PackedVector2Array()
		var arr: PackedVector2Array = segs[col]
		arr.append(centre)
		arr.append(tip)
		if not matched:
			ends.append([tip, col])
		if col.v > hub_col.v or hub_col.a == 0.0:
			hub_col = col
	hubs.append([centre, degree, hub_col, c])


func _draw_collected(ci: CanvasItem, segs: Dictionary, hubs: Array, ends: Array) -> void:
	var core_w := 0.13 * _unit * (1.3 if palette.high_contrast else 1.0)
	if high_effects:
		_draw_quads(ci, segs, 0.78 * _unit, _glow_tex, 1)
	_draw_quads(ci, segs, core_w, _core_tex, 0)
	# Neon "hot core": a thin bright filament on energised arms.
	_draw_quads(ci, segs, core_w * 0.36, _core_tex, 2)
	var r_joint := core_w * 0.5
	for e in ends:
		ci.draw_circle(e[0], r_joint * 1.25, e[1], true, -1.0, true)
	for h in hubs:
		var pos: Vector2 = h[0]
		var degree: int = h[1]
		var col: Color = h[2]
		var cell: int = h[3]
		if degree == 1:
			ci.draw_arc(pos, 0.2 * _unit, 0.0, TAU, 28, col, core_w * 0.55, true)
			ci.draw_circle(pos, 0.085 * _unit, col.lerp(palette.hub, 0.45), true, -1.0, true)
		elif puzzle.locked[cell] == 1:
			var r := r_joint * 1.5
			ci.draw_rect(Rect2(pos - Vector2(r, r), Vector2(r, r) * 2.0), col.lerp(palette.hub, 0.35))
		else:
			ci.draw_circle(pos, r_joint * (1.45 if degree >= 3 else 1.0), col.lerp(palette.hub, 0.2 if degree >= 3 else 0.0), true, -1.0, true)


## Batches every arm segment into one textured triangle array.
## pass_kind: 0 = core, 1 = soft glow (low alpha), 2 = hot filament (only
## for bright, energised arms).
func _draw_quads(ci: CanvasItem, segs: Dictionary, width: float, tex: Texture2D, pass_kind: int) -> void:
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var half := width * 0.5
	for key in segs.keys():
		var col: Color = key
		var bright := col.v > 0.55 and col.s > 0.0
		if pass_kind == 1:
			col = Color(col, (0.45 if bright else 0.1) * col.a)
		elif pass_kind == 2:
			if not bright:
				continue
			col = Color(col.lerp(Color.WHITE, 0.6), col.a)
		var arr: PackedVector2Array = segs[key]
		for i in range(0, arr.size(), 2):
			var a := arr[i]
			var b := arr[i + 1]
			var dir := b - a
			var seg_len := dir.length()
			if seg_len <= 0.0001:
				continue
			var n := Vector2(-dir.y, dir.x) / seg_len * half
			var base := points.size()
			points.append(a - n)
			points.append(a + n)
			points.append(b + n)
			points.append(b - n)
			uvs.append(Vector2(0, 0))
			uvs.append(Vector2(1, 0))
			uvs.append(Vector2(1, 1))
			uvs.append(Vector2(0, 1))
			for k in 4:
				colors.append(col)
			indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	if points.is_empty():
		return
	RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), indices, points, colors, uvs,
			PackedInt32Array(), PackedFloat32Array(), tex.get_rid())


func _collect_lock_marks(c: int, marks: PackedVector2Array) -> void:
	var poly := puzzle.topology.cell_polygon(c)
	var centre := puzzle.topology.cell_center(c)
	var count := poly.size()
	for i in count:
		var v := centre + (poly[i] - centre) * 0.82
		var prev := centre + (poly[(i + count - 1) % count] - centre) * 0.82
		var nxt := centre + (poly[(i + 1) % count] - centre) * 0.82
		marks.append(v)
		marks.append(v.lerp(prev, 0.22))
		marks.append(v)
		marks.append(v.lerp(nxt, 0.22))


## Linked tiles: a coloured inset outline plus a diamond badge per group
## (letters too in colour-blind mode).
func _draw_link_badges(ci: CanvasItem) -> void:
	var topo := puzzle.topology
	for g in puzzle.link_groups.size():
		var col := palette.group_color(g)
		for c in puzzle.link_groups[g]:
			var centre := topo.cell_center(c)
			var poly := topo.cell_polygon(c)
			var outline := PackedVector2Array()
			for v in poly:
				outline.append(centre + (v - centre) * 0.86)
			outline.append(outline[0])
			ci.draw_polyline(outline, Color(col, 0.55), 0.035 * _unit, true)
			var p := centre + Vector2(0.3, -0.3) * _unit
			var r := 0.1 * _unit
			var pts := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)])
			ci.draw_colored_polygon(pts, col)
			if palette.colorblind:
				_draw_label(ci, p + Vector2(0.0, 0.2 * _unit), char(65 + g % 26), 0.16 * _unit, col)


func _paint_fx(ci: CanvasItem) -> void:
	if puzzle == null:
		return
	var topo := puzzle.topology
	# Rotating and shaking tiles.
	var segs := {}
	var hubs: Array = []
	var ends: Array = []
	for c in _animating.keys():
		_collect_tile(c, _anim_angle[c], segs, hubs, ends)
	for c in _shake.keys():
		var t: float = _shake[c]
		_collect_tile(c, sin(t * 60.0) * 0.12 * t, segs, hubs, ends)
	_draw_collected(ci, segs, hubs, ends)

	# Cores: pulsing reactor glyph.
	for i in puzzle.cores.size():
		var c := puzzle.cores[i]
		var p := topo.cell_center(c)
		var col := palette.core_color(i)
		var pulse := 0.5 + 0.5 * sin(_time * 3.0 + i)
		ci.draw_circle(p, (0.36 + 0.04 * pulse) * _unit, Color(col, 0.14 + 0.08 * pulse))
		ci.draw_arc(p, 0.3 * _unit, 0.0, TAU, 32, col, 0.05 * _unit, true)
		var hex := PackedVector2Array()
		for k in 6:
			hex.append(p + Vector2.from_angle(_time * 0.6 + k * TAU / 6.0) * 0.17 * _unit)
		ci.draw_colored_polygon(hex, col.lerp(palette.hub, 0.3 + 0.3 * pulse))
		if palette.colorblind and puzzle.cores.size() > 1:
			_draw_label(ci, p + Vector2(0, 0.06 * _unit), str(i + 1), 0.2 * _unit, palette.bg_bottom)

	# Portals: counter-rotating rings, paired by colour (and letter).
	for i in puzzle.portal_count():
		var col := palette.group_color(i + 3)
		for k in 2:
			var c := puzzle.portal_pairs[i * 2 + k]
			var p := topo.cell_center(c)
			for ring in 2:
				var r := (0.3 - ring * 0.08) * _unit
				var spin := _time * (1.4 if ring == 0 else -2.0)
				for seg in 3:
					var a0 := spin + seg * TAU / 3.0
					ci.draw_arc(p, r, a0, a0 + TAU / 5.0, 10, Color(col, 0.9 - ring * 0.3), 0.045 * _unit, true)
			_draw_label(ci, p + Vector2(0.28, 0.36) * _unit, char(65 + i % 26), 0.17 * _unit, col)

	# Hint / selection highlight.
	if not _highlight.is_empty():
		var a := 0.55 + 0.45 * sin(_highlight_t * 6.0)
		for c in _highlight:
			var poly := topo.cell_polygon(c)
			poly.append(poly[0])
			ci.draw_polyline(poly, Color(palette.ui_accent, a), 0.06 * _unit, true)

	# Link focus: show every member of the touched group.
	if _link_focus >= 0 and _link_focus < puzzle.link_groups.size():
		var g := puzzle.link_groups[_link_focus]
		var col := palette.group_color(_link_focus)
		for i in range(1, g.size()):
			ci.draw_dashed_line(topo.cell_center(g[0]), topo.cell_center(g[i]), Color(col, 0.6), 0.04 * _unit, 0.15 * _unit)

	# Victory glow overlay.
	if _victory_t >= 0.0:
		var glow := 1.0 - clampf((_victory_t - (_victory_end - 0.4)) / 0.4, 0.0, 1.0) if _victory_done else 1.0
		if _victory_done:
			glow = 0.0
		if glow > 0.0 and high_effects:
			var bs := topo.board_size()
			var ring := clampf(_victory_t / maxf(_victory_end, 0.01), 0.0, 1.0)
			ci.draw_arc(bs * 0.5, bs.length() * 0.5 * ring, 0.0, TAU, 48, Color(palette.lit, 0.12 * (1.0 - ring)), 0.3 * _unit)


func _draw_label(ci: CanvasItem, at: Vector2, text: String, height: float, col: Color) -> void:
	var font := UiTheme.bold_font()
	var px := 32
	var s := height / float(px)
	ci.draw_set_transform(at, 0.0, Vector2(s, s))
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, px).x
	ci.draw_string(font, Vector2(-w * 0.5, px * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# --- Input --------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if puzzle == null or attract:
		return
	if event is InputEventScreenTouch:
		_on_touch(event)
		accept_event()
	elif event is InputEventScreenDrag:
		_on_drag(event)
		accept_event()
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		_on_mouse_button(event)
		accept_event()
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		if _mouse_down:
			_drag_single(event.position, event.relative)
		accept_event()


func _on_touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		_touches[e.index] = e.position
		if _touches.size() == 1:
			_begin_press(e.position)
		elif _touches.size() == 2:
			_press_active = false
			var pts: Array = _touches.values()
			_pinch_dist = maxf(1.0, (pts[0] as Vector2).distance_to(pts[1]))
			_pinch_zoom = zoom
			_pinch_mid = ((pts[0] as Vector2) + (pts[1] as Vector2)) * 0.5
			_pinch_pan = pan
			_two_finger_start = _time
			_two_finger_moved = false
	else:
		var was_two := _touches.size() == 2
		_touches.erase(e.index)
		if was_two:
			if _two_finger_start >= 0.0 and not _two_finger_moved and _time - _two_finger_start < 0.3:
				gesture_used.emit("two_finger")
				two_finger_tapped.emit()
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
			var new_zoom := clampf(_pinch_zoom * dist / _pinch_dist, 1.0, _max_zoom())
			var ratio := new_zoom / maxf(zoom, 0.001)
			var centre := size * 0.5
			pan = (pan + centre - mid) * ratio - centre + mid
			pan += mid - _pinch_mid
			_pinch_mid = mid
			zoom = new_zoom
			_clamp_camera()
			_apply_transform()
			gesture_used.emit("pinch")
	elif _touches.size() == 1:
		_drag_single(e.position, e.relative)


func _drag_single(pos: Vector2, relative: Vector2) -> void:
	if not _dragging and pos.distance_to(_press_pos) > DRAG_THRESHOLD:
		_dragging = true
		_press_active = false
	if _dragging and zoom > 1.001:
		pan += relative
		_clamp_camera()
		_apply_transform()
		gesture_used.emit("drag")


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
			if e.pressed and interactive:
				var c := cell_at_local(e.position)
				if c >= 0:
					cell_tapped.emit(c, -1)
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if e.pressed:
				var factor := 1.12 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12
				_zoom_at(e.position, zoom * factor)


func _zoom_at(at: Vector2, new_zoom: float) -> void:
	var z := clampf(new_zoom, 1.0, _max_zoom())
	var ratio := z / zoom
	var centre := size * 0.5
	pan = (pan + centre - at) * ratio - centre + at
	zoom = z
	_clamp_camera()
	_apply_transform()


func _begin_press(pos: Vector2) -> void:
	_press_active = true
	_press_pos = pos
	_press_time = _time
	_press_cell = cell_at_local(pos)
	_long_fired = false
	_dragging = false
	if _press_cell >= 0 and puzzle.link_of[_press_cell] >= 0:
		_link_focus = puzzle.link_of[_press_cell]
	set_process(true)


func _end_press(pos: Vector2) -> void:
	var was_active := _press_active
	_press_active = false
	_link_focus = -1
	_fx_layer.queue_redraw()
	if not was_active or _dragging or _long_fired or not interactive:
		_dragging = false
		return
	var cell := cell_at_local(pos)
	if cell != _press_cell:
		return
	var double := _time - _last_tap_time < DOUBLE_TAP and cell == _last_tap_cell
	_last_tap_time = -10.0 if double else _time
	_last_tap_cell = cell
	if cell < 0:
		if double:
			empty_double_tapped.emit()
		return
	if double:
		cell_double_tapped.emit(cell)
	else:
		cell_tapped.emit(cell, 1)
