extends TestCase

const N := 1
const E := 2
const S := 4
const W := 8


func _square(w: int, h: int, masks: Array) -> Puzzle:
	var p := Puzzle.create(SquareTopology.new(w, h))
	for i in masks.size():
		p.masks[i] = masks[i]
	p.finalize()
	return p


func test_mirror_images_share_fingerprint() -> void:
	# Corner pointing E+S in the top-left vs its mirror in the top-right.
	var a := _square(3, 2, [E | S, W, 0, N, 0, 0])
	var b := _square(3, 2, [0, E, W | S, 0, 0, N])
	assert_eq(Fingerprint.compute(a), Fingerprint.compute(b))


func test_rotated_square_board_shares_fingerprint() -> void:
	var a := _square(2, 2, [E, W | S, 0, N])
	# Rotate 90 degrees clockwise: (x, y) -> (h-1-y, x), masks rotate by one.
	var b := Puzzle.create(SquareTopology.new(2, 2))
	for c in 4:
		var x := c % 2
		var y := c / 2
		var nx := 1 - y
		var ny := x
		b.masks[ny * 2 + nx] = Topology.rotate_mask(a.masks[c], 1, 4)
	b.finalize()
	assert_eq(Fingerprint.compute(a), Fingerprint.compute(b))


func test_different_boards_differ() -> void:
	var a := _square(2, 2, [E, W, E, W])
	var b := _square(2, 2, [E | S, W | S, N | E, N | W])
	assert_ne(Fingerprint.compute(a), Fingerprint.compute(b))


func test_feature_distance() -> void:
	var p := PuzzleGenerator.new().generate(SeedManager.level_request(60))
	var q := PuzzleGenerator.new().generate(SeedManager.level_request(61))
	var fp := Fingerprint.features(p)
	assert_true(Fingerprint.too_similar(fp, fp))
	assert_true(Fingerprint.distance(fp, Fingerprint.features(q)) > 0.0)
