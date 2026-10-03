class_name BoardView
extends Control
## Renders a puzzle and converts touch / mouse gestures into intents.
##
## Puzzle *data* is drawn by a few batched canvas layers instead of one Node
## per tile (spec §48-49):
##   cells     - dot matrix marking the board, anchor plates
##   glow      - additive halo of every energised pipe (resting tiles)
##   tiles     - every resting tile, rebuilt only when the board changes
##   fx glow   - additive: rotating tiles, core orbs, portals
##   fx        - rotating tiles, glyphs, hint rings, touch ripples
##   particles - pooled additive particles
## Tiles are assembled from pre-tessellated PipeGeometry templates, so a
## redraw is native array work. All geometry is in board units; one Node2D
## transform maps it to pixels (zoom / pan / camera pulse).

signal cell_tapped(cell: int, steps: int)
signal cell_double_tapped(cell: int)
signal empty_double_tapped
signal two_finger_tapped
signal gesture_used(kind: String)
signal victory_finished

const MIN_CELL_PX := 34.0
const MAX_CELL_PX := 150.0
const SPRING_K := 340.0
const SPRING_DAMP := 24.0
const PADDING := 18.0
const RIPPLE_TIME := 0.42

const PIPE_SHADER := "res://shaders/pipe_gradient.gdshader"

## Cross-section profiles: crisp anti-aliased core and soft gaussian glow.
static var _core_tex: ImageTexture
static var _glow_tex: ImageTexture
static var _pipe_shader: Shader
static var _pipe_shader_add: Shader

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
var _glow_layer: Layer
var _tiles_layer: Layer
var _fx_glow_layer: Layer
var _fx_layer: Layer
var _geo: PipeGeometry
var _pipe_materials: Array[ShaderMaterial] = []
## Per-cell geometry of resting tiles: [key, points, colours, uvs], rebuilt
## only when the inputs packed into the key change (see _tile_key).
var _core_cache: Array = []
var _glow_cache: Array = []
var _disc_node: Array = []
var _disc_inner: Array = []
var _disc_hub: Array = []
var _disc_bead: Array = []
var _disc_halo: Array = []
var _disc_orb: Array = []
var _disc_orb_core: Array = []

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
var _ripples: Array = []

var _victory_t := -1.0
var _victory_start := PackedFloat32Array()
var _victory_end := 0.0
var _victory_fired := PackedByteArray()
var _victory_done := false
var _pulse_t := -1.0
var _attract_timer := 0.0

var _gestures: BoardGestures


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
	if _core_tex == null:
		_core_tex = PipeGeometry.profile_texture(true)
		_glow_tex = PipeGeometry.profile_texture(false)
	_canvas = Node2D.new()
	add_child(_canvas)
	_cells_layer = _make_layer(_paint_cells, false)
	_glow_layer = _make_layer(_paint_glow, true)
	_tiles_layer = _make_layer(_paint_tiles, false)
	_fx_glow_layer = _make_layer(_paint_fx_glow, true)
	_fx_layer = _make_layer(_paint_fx, false)
	particles = ParticleField.new()
	_canvas.add_child(particles)
	_gestures = BoardGestures.new(self)
	resized.connect(_layout)


func _make_layer(painter: Callable, additive: bool) -> Layer:
	var layer := Layer.new()
	layer.painter = painter
	if _pipe_shader == null:
		_pipe_shader = load(PIPE_SHADER)
		_pipe_shader_add = Shader.new()
		_pipe_shader_add.code = _pipe_shader.code.replace("render_mode blend_mix;", "render_mode blend_add;")
	var mat := ShaderMaterial.new()
	mat.shader = _pipe_shader_add if additive else _pipe_shader
	layer.material = mat
	_pipe_materials.append(mat)
	_canvas.add_child(layer)
	return layer


## Feeds the gradient stops and board size to the pipe shaders.
func _sync_gradient() -> void:
	var bs := puzzle.topology.board_size() if puzzle else Vector2.ONE
	for mat in _pipe_materials:
		mat.set_shader_parameter("lit", palette.lit)
		mat.set_shader_parameter("lit2", palette.lit2)
		mat.set_shader_parameter("board_size", bs)


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
	_ripples.clear()
	_highlight = PackedInt32Array()
	_victory_t = -1.0
	_victory_done = false
	_pulse_t = -1.0
	_link_focus = -1
	particles.clear()
	_unit = p.topology.apothem() * 2.0
	_geo = PipeGeometry.for_topology(p.topology)
	_invalidate_tiles()
	var cw := _geo.core_width
	_disc_node = PipeGeometry.disc(0.17 * _unit)
	_disc_inner = PipeGeometry.disc(0.08 * _unit)
	_disc_hub = PipeGeometry.disc(cw * 0.95)
	_disc_bead = PipeGeometry.disc(cw * 0.78, 12)
	_disc_halo = PipeGeometry.disc(0.42 * _unit)
	_disc_orb = PipeGeometry.disc(0.62 * _unit, 28)
	_disc_orb_core = PipeGeometry.disc(0.2 * _unit, 24)
	zoom = 1.0
	pan = Vector2.ZERO
	_pending_auto_zoom = true
	_layout()
	refresh()
	_cells_layer.queue_redraw()
	set_process(true)


func set_palette(p: Palette) -> void:
	palette = p
	_invalidate_tiles()
	for layer in [_cells_layer, _glow_layer, _tiles_layer, _fx_glow_layer, _fx_layer]:
		(layer as Layer).queue_redraw()


func _set_effects(speed: float, reduced: bool, high: bool) -> void:
	animation_speed = clampf(speed, 0.25, 3.0)
	reduce_motion = reduced
	high_effects = high
	particles.density = (1.0 if high else 0.45) * (0.4 if reduced else 1.0)
	if _glow_layer:
		_glow_layer.queue_redraw()


## Applies the accessibility / effects settings dictionary from the save.
func apply_user_settings(settings: Dictionary) -> void:
	_set_effects(float(settings.get("animation_speed", 1.0)), bool(settings.get("reduce_motion", false)),
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
	_redraw_tiles()


func _redraw_tiles() -> void:
	_glow_layer.queue_redraw()
	_tiles_layer.queue_redraw()
	_fx_glow_layer.queue_redraw()
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
		zoom = minf(MIN_CELL_PX / cell_px, max_zoom())
	_clamp_camera()
	_apply_transform()


func max_zoom() -> float:
	return maxf(1.0, MAX_CELL_PX / maxf(_fit * _unit, 1.0))


func reset_view() -> void:
	zoom = 1.0
	pan = Vector2.ZERO
	_apply_transform()


func _clamp_camera() -> void:
	zoom = clampf(zoom, 1.0, max_zoom())
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


func _local_to_board(p: Vector2) -> Vector2:
	return _canvas.transform.affine_inverse() * p


func cell_at_local(p: Vector2) -> int:
	if puzzle == null:
		return -1
	var c := puzzle.topology.cell_at(_local_to_board(p))
	if c < 0 or puzzle.active[c] == 0:
		return -1
	return c


# --- Animation API ------------------------------------------------------------

## Called after the model rotated `cells` by `steps`: animate from the old
## orientation with a springy settle.
func animate_rotation(cells: PackedInt32Array, steps: int) -> void:
	var step := puzzle.topology.step_angle()
	for c in cells:
		_anim_angle[c] -= steps * step
		_anim_vel[c] = 0.0
		_animating[c] = true
	refresh()
	set_process(true)


## Expanding ring where the player touched (tap feedback).
func ripple(cell: int) -> void:
	if puzzle == null or cell < 0 or reduce_motion:
		return
	_ripples.append([puzzle.topology.cell_center(cell), 0.0])
	set_process(true)


## Feedback for refused taps (locked / pinned tiles).
func shake(cell: int) -> void:
	_shake[cell] = 0.3
	_redraw_tiles()
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
			particles.burst(at, _lit_at(c).lerp(Color.WHITE, 0.3), 6, 2.6 * _unit, 0.4, 0.045 * _unit)


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
	var starts := PackedInt32Array()
	for c in origins:
		if c >= 0 and c < puzzle.cell_count():
			starts.append(c)
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
		_glow_layer.queue_redraw()
		_tiles_layer.queue_redraw()
	busy = busy or not _animating.is_empty()

	for c in _shake.keys():
		_shake[c] -= delta
		if _shake[c] <= 0.0:
			_shake.erase(c)
			_redraw_tiles()
	busy = busy or not _shake.is_empty()

	for i in range(_ripples.size() - 1, -1, -1):
		_ripples[i][1] += delta
		if _ripples[i][1] >= RIPPLE_TIME:
			_ripples.remove_at(i)
	busy = busy or not _ripples.is_empty()

	if not _highlight.is_empty():
		_highlight_t += delta
		busy = true

	if _victory_t >= 0.0 and not _victory_done:
		_victory_t += delta
		_victory_particles()
		_glow_layer.queue_redraw()
		_tiles_layer.queue_redraw()
		if _victory_t >= _victory_end - 0.4 / animation_speed and _pulse_t < 0.0:
			_pulse_t = 0.0
			_final_burst()
		if _victory_t >= _victory_end:
			_victory_done = true
			_glow_layer.queue_redraw()
			_tiles_layer.queue_redraw()
			victory_finished.emit()
		busy = true

	if _pulse_t >= 0.0:
		_pulse_t += delta
		if _pulse_t > 0.4:
			_pulse_t = -1.0
		_apply_transform()
		busy = true

	if _gestures.update():
		busy = true

	if attract:
		_attract_timer -= delta
		if _attract_timer <= 0.0:
			_attract_timer = 5.5
			play_victory(puzzle.cores if not puzzle.cores.is_empty() else PackedInt32Array([_random_tile()]))
		busy = true

	# Cores and portals breathe continuously.
	var living := not puzzle.cores.is_empty() or puzzle.portal_count() > 0
	if living or busy:
		_fx_glow_layer.queue_redraw()
		_fx_layer.queue_redraw()
	if not busy and not living and particles.count() == 0:
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
		var col := _lit_at(c).lerp(Color.WHITE, 0.25)
		var centre := topo.cell_center(c)
		for d in dc:
			if (m >> d) & 1 == 0:
				continue
			var other := puzzle.nbr[c * dc + d]
			if other >= 0 and _victory_start[other] > _victory_start[c]:
				var dur := maxf(0.05, _victory_start[other] - _victory_start[c])
				particles.comet(centre, topo.cell_center(other), dur, col, 0.04 * _unit)
		if high_effects and (c % 3 == 0):
			particles.burst(centre, Color(col, 0.6), 2, 1.2 * _unit, 0.45, 0.035 * _unit)


func _final_burst() -> void:
	var topo := puzzle.topology
	var origins := puzzle.cores if not puzzle.cores.is_empty() else PackedInt32Array([_center_cell()])
	for c in origins:
		particles.burst(topo.cell_center(c), Color.WHITE, 26, 7.0 * _unit, 0.9, 0.06 * _unit)
	var bs := topo.board_size()
	for i in 18:
		var at := Vector2(fmod(i * 7.31, 1.0) * bs.x, fmod(i * 3.77, 1.0) * bs.y)
		particles.burst(at, Color(palette.lit2, 0.8), 2, 3.0 * _unit, 0.7, 0.045 * _unit)


# --- Colours ------------------------------------------------------------------

## Brightness 0..1 of a tile during the victory wave (1 after it).
func _victory_level(c: int) -> float:
	if _victory_done:
		return 1.0
	if _victory_t < 0.0 or _victory_start.size() <= c or _victory_start[c] < 0.0:
		return 0.0
	return clampf((_victory_t - _victory_start[c]) / 0.22, 0.0, 1.0)


## Energised colour of a cell: its core's colour, or the theme gradient that
## sweeps across the board.
func _lit_at(c: int) -> Color:
	if _uses_core_colour(c):
		return palette.core_color(_power[c])
	return palette.lit.lerp(palette.lit2, _gradient_t(c))


func _uses_core_colour(c: int) -> bool:
	return GameMode.uses_cores(puzzle.mode) and _power.size() > c and _power[c] >= 0


## Position of a tile centre along the theme gradient (same formula as the
## pipe shader uses per vertex).
func _gradient_t(c: int) -> float:
	var p := puzzle.topology.cell_center(c)
	var bs := puzzle.topology.board_size()
	return clampf((p.x / bs.x) * 0.55 + (p.y / bs.y) * 0.45, 0.0, 1.0)


func _idle() -> Color:
	return palette.pipe_idle


## Returns [colour, glows, follows theme gradient] for one arm.
func _arm_style(c: int, d: int, settled: bool) -> Array:
	var matched := settled and (_matched[c] >> d) & 1 == 1
	var col := _idle()
	var glows := false
	var grad := false
	match puzzle.mode:
		GameMode.DARK:
			var good := settled and _dark_good.size() > c and (_dark_good[c] >> d) & 1 == 1
			col = _lit_at(c) if good else palette.warn
			glows = true
			grad = good
		GameMode.CORE, GameMode.MULTI:
			var owner := _power[c] if _power.size() > c else -1
			if owner == Connectivity.CONFLICT:
				col = palette.warn
				glows = true
			elif owner >= 0:
				col = palette.core_color(owner) if matched else Color(palette.core_color(owner), 0.55)
				glows = matched
			elif matched:
				col = Color(palette.ui_text, 0.5)
		_:
			if matched:
				col = _lit_at(c)
				glows = true
				grad = true
	var v := _victory_level(c)
	if v > 0.0:
		col = Color(col.lerp(_lit_at(c).lerp(Color.WHITE, 0.35), v * 0.7), maxf(col.a, v))
		glows = true
		grad = not _uses_core_colour(c)
	return [col, glows, grad]


# --- Geometry assembly --------------------------------------------------------

## `uv_xf` (see _grad_uv) flags the vertices for the shader gradient.
func _append(tpl: Array, xf: Transform2D, col: Color, pts: PackedVector2Array, cols: PackedColorArray, uvs: PackedVector2Array,
		uv_xf := Transform2D.IDENTITY) -> void:
	var tp: PackedVector2Array = tpl[0]
	pts.append_array(xf * tp)
	if uv_xf == Transform2D.IDENTITY:
		uvs.append_array(tpl[1])
	else:
		uvs.append_array(uv_xf * (tpl[1] as PackedVector2Array))
	var ca := PackedColorArray()
	ca.resize(tp.size())
	ca.fill(col)
	cols.append_array(ca)


## Adds one tile (core strokes or glow halo) to the batch arrays.
func _emit_tile(c: int, angle: float, glow: bool, pts: PackedVector2Array, cols: PackedColorArray, uvs: PackedVector2Array) -> void:
	var m := state.mask(c)
	if m == 0:
		return
	var topo := puzzle.topology
	var dc := topo.dir_count
	var centre := topo.cell_center(c)
	var xf := Transform2D(angle, centre)
	var settled := angle == 0.0
	var arms := PackedInt32Array()
	for d in dc:
		if (m >> d) & 1 == 1:
			arms.append(d)
	var deg := arms.size()
	var styles: Array = []
	for d in arms:
		var st := _arm_style(c, d, settled)
		if not glow:
			st[0] = palette.solid(st[0])
		styles.append(st)
	# Keeps UV.x, sets UV.y = 2 + gradient position of this tile (natively).
	var grad_uv := Transform2D(Vector2(1, 0), Vector2.ZERO, Vector2(0.0, 2.0 + _gradient_t(c)))
	var glow_boost := 1.0 + _victory_level(c) * 0.8
	for k in deg:
		var a := arms[k]
		var col: Color = styles[k][0]
		var uv_xf := grad_uv if bool(styles[k][2]) else Transform2D.IDENTITY
		if glow:
			if not bool(styles[k][1]):
				continue
			col = Color(col, 0.42 * glow_boost)
		var tpl: Array
		if deg == 2:
			var b := arms[1 - k]
			tpl = _geo.half_glow[a * dc + b] if glow else _geo.half_core[a * dc + b]
		else:
			tpl = _geo.spoke_glow[a] if glow else _geo.spoke_core[a]
		_append(tpl, xf, col, pts, cols, uvs, uv_xf)
		if glow:
			# Round off every place where this halo would end abruptly.
			if not settled or (_matched[c] >> a) & 1 == 0:
				_append(_geo.tip_cap_glow[a], xf, col, pts, cols, uvs, uv_xf)
			if deg != 2:
				_append(_geo.centre_cap_glow[a], xf, col, pts, cols, uvs, uv_xf)
			elif not bool(styles[1 - k][1]):
				_append(_geo.mid_cap_glow[a * dc + arms[1 - k]], xf, col, pts, cols, uvs, uv_xf)
	if glow:
		if deg == 1 and bool(styles[0][1]):
			var halo_uv := grad_uv if bool(styles[0][2]) else Transform2D.IDENTITY
			_append(_disc_halo, xf, Color(styles[0][0], 0.5 * glow_boost), pts, cols, uvs, halo_uv)
		return
	# Hubs, terminal nodes and open-end beads.
	var best := 0
	for k in deg:
		var sc: Color = styles[k][0]
		var bc: Color = styles[best][0]
		if sc.a * sc.v > bc.a * bc.v:
			best = k
	var brightest: Color = styles[best][0]
	var hub_uv := grad_uv if bool(styles[best][2]) else Transform2D.IDENTITY
	if deg == 1:
		_append(_disc_node, xf, brightest, pts, cols, uvs, hub_uv)
		_append(_disc_inner, xf, palette.bg_bottom.lerp(brightest, 0.15), pts, cols, uvs)
	elif deg >= 3:
		_append(_disc_hub, xf, brightest, pts, cols, uvs, hub_uv)
	for k in deg:
		var d := arms[k]
		var open := not settled or (_matched[c] >> d) & 1 == 0
		if not open:
			continue
		var uv_xf := grad_uv if bool(styles[k][2]) else Transform2D.IDENTITY
		if puzzle.mode == GameMode.DARK:
			_append(_geo.tip_cap_core[d], xf, styles[k][0], pts, cols, uvs, uv_xf)
		else:
			var tip := xf * (topo.dir_vector(d) * topo.apothem())
			_append(_disc_bead, Transform2D(0.0, tip), styles[k][0], pts, cols, uvs, uv_xf)


func _invalidate_tiles() -> void:
	_core_cache.clear()
	_glow_cache.clear()
	if puzzle:
		_core_cache.resize(puzzle.cell_count())
		_glow_cache.resize(puzzle.cell_count())


## Everything a resting tile's look depends on (besides the palette, which
## clears the caches): rotation, matched arms, owning core, DARK verdicts
## and the quantised victory brightness.
func _tile_key(c: int) -> int:
	var key := state.mask(c) | ((_matched[c] & 0x3F) << 6)
	if _power.size() > c:
		key |= ((_power[c] + 4) & 0xFF) << 12
	if _dark_good.size() > c:
		key |= (_dark_good[c] & 0x3F) << 20
	return key | (roundi(_victory_level(c) * 24.0) << 26)


## Appends a resting tile from the cache, rebuilding it when stale.
func _append_resting(c: int, glow: bool, pts: PackedVector2Array, cols: PackedColorArray, uvs: PackedVector2Array) -> void:
	var cache := _glow_cache if glow else _core_cache
	if cache.size() != puzzle.cell_count():
		_invalidate_tiles()
		cache = _glow_cache if glow else _core_cache
	var key := _tile_key(c)
	var entry = cache[c]
	if entry == null or int(entry[0]) != key:
		var tp := PackedVector2Array()
		var tc := PackedColorArray()
		var tu := PackedVector2Array()
		_emit_tile(c, 0.0, glow, tp, tc, tu)
		entry = [key, tp, tc, tu]
		cache[c] = entry
	pts.append_array(entry[1])
	cols.append_array(entry[2])
	uvs.append_array(entry[3])


func _flush(ci: CanvasItem, pts: PackedVector2Array, cols: PackedColorArray, uvs: PackedVector2Array, tex: Texture2D) -> void:
	if pts.is_empty():
		return
	RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), PackedInt32Array(), pts, cols, uvs,
			PackedInt32Array(), PackedFloat32Array(), tex.get_rid())


func _resting(c: int) -> bool:
	return puzzle.active[c] == 1 and not _animating.has(c) and not _shake.has(c)


# --- Painting -----------------------------------------------------------------

func _paint_cells(ci: CanvasItem) -> void:
	if puzzle == null:
		return
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var dot := PipeGeometry.disc(0.05 * _unit, 10)
	var plate := PipeGeometry.disc(0.46 * _unit, 24)
	var dot_col := Color(palette.ui_text, 0.13)
	var plate_col := Color(palette.ui_text, 0.05)
	for c in puzzle.cell_count():
		if puzzle.active[c] == 0:
			continue
		var xf := Transform2D(0.0, puzzle.topology.cell_center(c))
		if puzzle.locked[c] == 1:
			_append(plate, xf, plate_col, pts, cols, uvs)
		_append(dot, xf, dot_col, pts, cols, uvs)
	_flush(ci, pts, cols, uvs, _core_tex)


func _paint_glow(ci: CanvasItem) -> void:
	if puzzle == null or not high_effects:
		return
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	for c in puzzle.cell_count():
		if _resting(c):
			_append_resting(c, true, pts, cols, uvs)
	_flush(ci, pts, cols, uvs, _glow_tex)


func _paint_tiles(ci: CanvasItem) -> void:
	if puzzle == null:
		return
	_sync_gradient()
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	for c in puzzle.cell_count():
		if _resting(c):
			_append_resting(c, false, pts, cols, uvs)
	_flush(ci, pts, cols, uvs, _core_tex)
	BoardGlyphs.anchor_marks(ci, puzzle, state, session, palette, _unit)
	BoardGlyphs.link_badges(ci, puzzle, palette, _unit)


func _paint_fx_glow(ci: CanvasItem) -> void:
	if puzzle == null:
		return
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	if high_effects:
		for c in _animating.keys():
			_emit_tile(c, _anim_angle[c], true, pts, cols, uvs)
	var topo := puzzle.topology
	for i in puzzle.cores.size():
		var pulse := 0.5 + 0.5 * sin(_time * 2.6 + i)
		var xf := Transform2D(0.0, topo.cell_center(puzzle.cores[i]))
		_append(_disc_orb, xf, Color(palette.core_color(i), 0.42 + 0.2 * pulse), pts, cols, uvs)
	for i in puzzle.portal_count():
		for k in 2:
			var xf := Transform2D(0.0, topo.cell_center(puzzle.portal_pairs[i * 2 + k]))
			_append(_disc_halo, xf, Color(palette.group_color(i + 3), 0.35), pts, cols, uvs)
	_flush(ci, pts, cols, uvs, _glow_tex)


func _paint_fx(ci: CanvasItem) -> void:
	if puzzle == null:
		return
	var topo := puzzle.topology
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	for c in _animating.keys():
		_emit_tile(c, _anim_angle[c], false, pts, cols, uvs)
	for c in _shake.keys():
		var t: float = _shake[c]
		_emit_tile(c, sin(t * 60.0) * 0.12 * t + 0.0001, false, pts, cols, uvs)
	# Core orbs: solid body with a bright heart.
	for i in puzzle.cores.size():
		var xf := Transform2D(0.0, topo.cell_center(puzzle.cores[i]))
		var col := palette.core_color(i)
		_append(_disc_orb_core, xf, col, pts, cols, uvs)
		_append(_disc_inner, xf, col.lerp(Color.WHITE, 0.75), pts, cols, uvs)
	_flush(ci, pts, cols, uvs, _core_tex)

	BoardGlyphs.core_rings(ci, puzzle, palette, _time, _unit)
	BoardGlyphs.portals(ci, puzzle, palette, _time, _unit)

	# Hint highlight: breathing ring.
	if not _highlight.is_empty():
		var a := 0.55 + 0.45 * sin(_highlight_t * 6.0)
		for c in _highlight:
			ci.draw_arc(topo.cell_center(c), 0.47 * _unit, 0.0, TAU, 36, Color(palette.ui_accent, a), 0.05 * _unit, true)

	# Touch ripples.
	for rp in _ripples:
		var t: float = rp[1] / RIPPLE_TIME
		ci.draw_arc(rp[0], (0.22 + 0.4 * t) * _unit, 0.0, TAU, 32, Color(palette.ui_text, 0.35 * (1.0 - t)), 0.03 * _unit, true)

	# Link focus: show every member of the touched group.
	if _link_focus >= 0 and _link_focus < puzzle.link_groups.size():
		var g := puzzle.link_groups[_link_focus]
		var col := palette.group_color(_link_focus)
		for i in range(1, g.size()):
			ci.draw_dashed_line(topo.cell_center(g[0]), topo.cell_center(g[i]), Color(col, 0.7), 0.035 * _unit, 0.15 * _unit)

	# Victory: expanding light ring.
	if _victory_t >= 0.0 and not _victory_done and high_effects:
		var bs := topo.board_size()
		var ring := clampf(_victory_t / maxf(_victory_end, 0.01), 0.0, 1.0)
		ci.draw_arc(bs * 0.5, bs.length() * 0.55 * ring, 0.0, TAU, 64, Color(palette.lit, 0.16 * (1.0 - ring)), 0.25 * _unit)


# --- Input --------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if puzzle == null or attract:
		return
	if _gestures.handle(event):
		accept_event()


## Camera change requested by a gesture (clamped to the board).
func set_camera(new_zoom: float, new_pan: Vector2) -> void:
	zoom = new_zoom
	pan = new_pan
	_clamp_camera()
	_apply_transform()


func zoom_at(at: Vector2, new_zoom: float) -> void:
	var z := clampf(new_zoom, 1.0, max_zoom())
	var ratio := z / zoom
	var centre := size * 0.5
	set_camera(z, (pan + centre - at) * ratio - centre + at)


## Highlights every member of a linked group while it is pressed (-1: none).
func set_link_focus(group: int) -> void:
	if group != _link_focus:
		_link_focus = group
		_fx_layer.queue_redraw()
