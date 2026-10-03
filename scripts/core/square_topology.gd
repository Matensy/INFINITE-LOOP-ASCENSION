class_name SquareTopology
extends Topology
## Classic square grid. Directions: 0 = N, 1 = E, 2 = S, 3 = W.

const DX: Array[int] = [0, 1, 0, -1]
const DY: Array[int] = [-1, 0, 1, 0]


func _init(w: int, h: int) -> void:
	kind = Kind.SQUARE
	width = maxi(1, w)
	height = maxi(1, h)
	dir_count = 4
	_build_neighbors()


func _offset(_x: int, _y: int, d: int) -> Vector2i:
	return Vector2i(DX[d], DY[d])


func cell_center(cell: int) -> Vector2:
	return Vector2(cell % width + 0.5, cell / width + 0.5)


func board_size() -> Vector2:
	return Vector2(width, height)


func apothem() -> float:
	return 0.5


func circumradius() -> float:
	return 0.70710678


func dir_angle(dir: int) -> float:
	return deg_to_rad(-90.0 + 90.0 * dir)


func cell_polygon(cell: int) -> PackedVector2Array:
	var c := cell_center(cell)
	return PackedVector2Array([
		c + Vector2(-0.5, -0.5), c + Vector2(0.5, -0.5),
		c + Vector2(0.5, 0.5), c + Vector2(-0.5, 0.5),
	])


func cell_at(point: Vector2) -> int:
	var x := floori(point.x)
	var y := floori(point.y)
	if x < 0 or y < 0 or x >= width or y >= height:
		return -1
	return y * width + x
