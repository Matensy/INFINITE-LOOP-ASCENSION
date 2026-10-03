class_name Topology
extends RefCounted
## Abstract board topology: cell layout, neighbourhood and geometry.
##
## Directions are indexed clockwise (screen space, y down). A connector mask
## stores one bit per direction, so rotating a piece clockwise by one step is a
## circular left shift of its mask. Geometry is expressed in "board units";
## the renderer scales board units to pixels.

enum Kind { SQUARE = 0, HEX = 1 }

var kind: int = Kind.SQUARE
var width: int = 0
var height: int = 0
var dir_count: int = 4
var cell_count: int = 0
## Flattened neighbour table: index cell * dir_count + dir -> cell or -1.
var neighbors: PackedInt32Array = PackedInt32Array()


func _build_neighbors() -> void:
	cell_count = width * height
	neighbors.resize(cell_count * dir_count)
	for c in cell_count:
		var x := c % width
		var y := c / width
		for d in dir_count:
			var off: Vector2i = _offset(x, y, d)
			var nx := x + off.x
			var ny := y + off.y
			if nx < 0 or ny < 0 or nx >= width or ny >= height:
				neighbors[c * dir_count + d] = -1
			else:
				neighbors[c * dir_count + d] = ny * width + nx


## Grid offset of the neighbour of (x, y) in direction d.
func _offset(_x: int, _y: int, _d: int) -> Vector2i:
	return Vector2i.ZERO


func neighbor(cell: int, dir: int) -> int:
	return neighbors[cell * dir_count + dir]


func opposite(dir: int) -> int:
	return (dir + dir_count / 2) % dir_count


func cell_x(cell: int) -> int:
	return cell % width


func cell_y(cell: int) -> int:
	return cell / width


func index_of(x: int, y: int) -> int:
	return y * width + x


## Centre of a cell in board units.
func cell_center(_cell: int) -> Vector2:
	return Vector2.ZERO


## Total extent of the board in board units.
func board_size() -> Vector2:
	return Vector2.ZERO


## Distance from cell centre to the midpoint of an edge.
func apothem() -> float:
	return 0.5


## Distance from cell centre to a vertex.
func circumradius() -> float:
	return 0.5


## Screen angle (radians, clockwise from +x) of direction d.
func dir_angle(_dir: int) -> float:
	return 0.0


func dir_vector(dir: int) -> Vector2:
	return Vector2.from_angle(dir_angle(dir))


## Angle covered by one rotation step.
func step_angle() -> float:
	return TAU / dir_count


## Polygon outline of a cell in board units.
func cell_polygon(_cell: int) -> PackedVector2Array:
	return PackedVector2Array()


## Cell containing a board-unit point, or -1.
func cell_at(_point: Vector2) -> int:
	return -1


func full_mask() -> int:
	return (1 << dir_count) - 1


func rotate(mask: int, steps: int) -> int:
	return Topology.rotate_mask(mask, steps, dir_count)


static func rotate_mask(mask: int, steps: int, n: int) -> int:
	var s := posmod(steps, n)
	if s == 0:
		return mask
	var full := (1 << n) - 1
	return ((mask << s) | (mask >> (n - s))) & full


static func popcount(mask: int) -> int:
	var count := 0
	var m := mask
	while m != 0:
		count += m & 1
		m >>= 1
	return count


## Number of distinct orientations of a mask (rotational period).
static func period(mask: int, n: int) -> int:
	for k in range(1, n + 1):
		if n % k == 0 and Topology.rotate_mask(mask, k, n) == mask:
			return k
	return n


## Smallest mask among all rotations; identifies the piece shape.
static func canonical(mask: int, n: int) -> int:
	var best := mask
	for k in range(1, n):
		var r := Topology.rotate_mask(mask, k, n)
		if r < best:
			best = r
	return best


## Name used in data/serialisation.
func kind_name() -> String:
	return "hex" if kind == Kind.HEX else "square"
