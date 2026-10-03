class_name BoardShapes
extends RefCounted
## Builds the set of active cells (the board outline). Shapes are defined in
## normalised board space so they work for every topology.

enum Shape { RECT, DIAMOND, ELLIPSE, CROSS, RING, INFINITY, STAR, ORGANIC, SPIRAL, HOLES }

const NAMES: Array[String] = [
	"rect", "diamond", "ellipse", "cross", "ring", "infinity", "star", "organic", "spiral", "holes",
]

## Approximate fraction of the bounding box kept by each shape. Used by the
## planner to size boards; the generator corrects any error in closed loop.
const FILL_RATIO: Array[float] = [1.0, 0.58, 0.8, 0.6, 0.6, 0.62, 0.55, 0.66, 0.55, 0.86]

## Smallest bounding box (in cells) where the shape still reads well.
const MIN_SIDE: Array[int] = [2, 5, 4, 5, 6, 6, 7, 5, 8, 5]

## Minimum fraction of cells that must survive, otherwise RECT is used.
const MIN_KEEP := 0.3


static func shape_name(shape: int) -> String:
	return NAMES[clampi(shape, 0, NAMES.size() - 1)]


static func shape_from_name(name: String) -> int:
	var idx := NAMES.find(name)
	return maxi(idx, 0)


## Returns a PackedByteArray (1 = active cell). Always non-empty and
## connected through the topology's neighbourhood.
static func build(shape: int, topo: Topology, rng: SeededRng) -> PackedByteArray:
	var active := PackedByteArray()
	active.resize(topo.cell_count)
	active.fill(1)
	if shape != Shape.RECT and mini(topo.width, topo.height) >= MIN_SIDE[shape]:
		var size := topo.board_size()
		var phase := rng.next_float() * TAU
		var seeds := _organic_seeds(rng)
		for c in topo.cell_count:
			var p := topo.cell_center(c)
			# Normalised coordinates in [-1, 1].
			var u := (p.x / size.x) * 2.0 - 1.0
			var v := (p.y / size.y) * 2.0 - 1.0
			active[c] = 1 if _inside(shape, u, v, phase, seeds) else 0
		if shape == Shape.HOLES:
			_punch_holes(active, topo, rng)
	_keep_largest_component(active, topo)
	var kept := 0
	for c in topo.cell_count:
		kept += active[c]
	if kept < maxi(2, int(topo.cell_count * MIN_KEEP)):
		active.fill(1)
	return active


static func _inside(shape: int, u: float, v: float, phase: float, seeds: Array) -> bool:
	# Thresholds sit slightly above 1.0 so edge cells are not lost to rounding.
	var r := sqrt(u * u + v * v)
	match shape:
		Shape.DIAMOND:
			return absf(u) + absf(v) <= 1.08
		Shape.ELLIPSE:
			return u * u + v * v <= 1.1
		Shape.CROSS:
			return absf(u) <= 0.38 or absf(v) <= 0.34
		Shape.RING:
			return r <= 1.08 and r >= 0.42
		Shape.INFINITY:
			# Two lobes stacked vertically (portrait friendly) joined at the waist.
			var top := u * u + (v + 0.5) * (v + 0.5) * 3.2
			var bottom := u * u + (v - 0.5) * (v - 0.5) * 3.2
			var lobe := minf(top, bottom)
			var hole := minf(
				u * u * 4.0 + (v + 0.5) * (v + 0.5) * 12.0,
				u * u * 4.0 + (v - 0.5) * (v - 0.5) * 12.0)
			return lobe <= 1.05 and hole >= 0.55
		Shape.STAR:
			var ang := atan2(v, u) + phase
			var limit := 0.62 + 0.42 * cos(5.0 * ang)
			return r <= maxf(limit, 0.45)
		Shape.ORGANIC:
			var field := 0.0
			for s in seeds:
				var sp: Vector3 = s
				var du := u - sp.x
				var dv := v - sp.y
				field += sp.z / (du * du + dv * dv + 0.05)
			return field >= 2.6
		Shape.SPIRAL:
			if r < 0.18:
				return true
			var ang := atan2(v, u) + phase
			var turns := 1.6
			var t := fposmod(r * turns - ang / TAU, 1.0)
			return t < 0.55 and r <= 1.05
		Shape.HOLES:
			return true
	return true


static func _organic_seeds(rng: SeededRng) -> Array:
	var seeds: Array = []
	var count := rng.range_int(3, 6)
	for i in count:
		seeds.append(Vector3(rng.range_float(-0.6, 0.6), rng.range_float(-0.6, 0.6), rng.range_float(0.25, 0.5)))
	return seeds


static func _punch_holes(active: PackedByteArray, topo: Topology, rng: SeededRng) -> void:
	var holes := maxi(1, topo.cell_count / 14)
	for i in holes:
		var c := rng.range_int(0, topo.cell_count - 1)
		active[c] = 0
		if rng.chance(0.35):
			var d := rng.range_int(0, topo.dir_count - 1)
			var n := topo.neighbor(c, d)
			if n >= 0:
				active[n] = 0


static func _keep_largest_component(active: PackedByteArray, topo: Topology) -> void:
	var comp := PackedInt32Array()
	comp.resize(topo.cell_count)
	comp.fill(-1)
	var best_id := -1
	var best_size := 0
	var next_id := 0
	var stack := PackedInt32Array()
	for start in topo.cell_count:
		if active[start] == 0 or comp[start] >= 0:
			continue
		var size := 0
		stack.clear()
		stack.append(start)
		comp[start] = next_id
		while not stack.is_empty():
			var c := stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			size += 1
			for d in topo.dir_count:
				var n := topo.neighbor(c, d)
				if n >= 0 and active[n] == 1 and comp[n] < 0:
					comp[n] = next_id
					stack.append(n)
		if size > best_size:
			best_size = size
			best_id = next_id
		next_id += 1
	for c in topo.cell_count:
		if active[c] == 1 and comp[c] != best_id:
			active[c] = 0
