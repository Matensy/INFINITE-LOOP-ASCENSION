class_name Puzzle
extends RefCounted
## Immutable description of a generated puzzle.
##
## `masks` stores every tile in its *solution* orientation. The player sees
## each tile rotated by `start_rot` clockwise steps; rotation 0 is therefore
## always a valid solution (other solutions may exist unless `unique`).

const FORMAT_VERSION := 1

var topology: Topology
var active: PackedByteArray = PackedByteArray()
var masks: PackedInt32Array = PackedInt32Array()
var start_rot: PackedInt32Array = PackedInt32Array()
var locked: PackedByteArray = PackedByteArray()
var mode: int = GameMode.LOOP
## Cells holding a power core (CORE / MULTI modes).
var cores: PackedInt32Array = PackedInt32Array()
## Flattened portal pairs: [a0, b0, a1, b1, ...]. Portals join two distant
## cells with an always-on link.
var portal_pairs: PackedInt32Array = PackedInt32Array()
## Linked tile groups: rotating one member rotates the whole group.
var link_groups: Array[PackedInt32Array] = []
## True when the solver proved the solution is unique.
var unique: bool = false
## Free-form metadata: seed, level, code, difficulty, tier, theme, shape, ...
var meta: Dictionary = {}

# Derived lookup tables (built by finalize()).
var nbr: PackedInt32Array = PackedInt32Array()
var portal_of: PackedInt32Array = PackedInt32Array()
var core_index: PackedInt32Array = PackedInt32Array()
var link_of: PackedInt32Array = PackedInt32Array()
var network_cell: PackedByteArray = PackedByteArray()


static func create(topo: Topology) -> Puzzle:
	var p := Puzzle.new()
	p.topology = topo
	var n := topo.cell_count
	p.active.resize(n)
	p.active.fill(1)
	p.masks.resize(n)
	p.start_rot.resize(n)
	p.locked.resize(n)
	return p


func cell_count() -> int:
	return topology.cell_count


func dir_count() -> int:
	return topology.dir_count


## Rebuilds derived tables. Must be called after any structural change.
func finalize() -> void:
	var n := topology.cell_count
	var dc := topology.dir_count
	nbr.resize(n * dc)
	for c in n:
		for d in dc:
			var other := topology.neighbor(c, d)
			if active[c] == 0 or other < 0 or active[other] == 0:
				other = -1
			nbr[c * dc + d] = other
	portal_of.resize(n)
	portal_of.fill(-1)
	for i in range(0, portal_pairs.size() - 1, 2):
		portal_of[portal_pairs[i]] = portal_pairs[i + 1]
		portal_of[portal_pairs[i + 1]] = portal_pairs[i]
	core_index.resize(n)
	core_index.fill(-1)
	for i in cores.size():
		core_index[cores[i]] = i
	link_of.resize(n)
	link_of.fill(-1)
	for g in link_groups.size():
		for c in link_groups[g]:
			link_of[c] = g
	network_cell.resize(n)
	for c in n:
		var is_net := active[c] == 1 and (masks[c] != 0 or core_index[c] >= 0 or portal_of[c] >= 0)
		network_cell[c] = 1 if is_net else 0


func neighbor(cell: int, dir: int) -> int:
	return nbr[cell * topology.dir_count + dir]


func mask_at(cell: int, rotation: int) -> int:
	return Topology.rotate_mask(masks[cell], rotation, topology.dir_count)


func period_of(cell: int) -> int:
	return Topology.period(masks[cell], topology.dir_count)


## True if the player can change this tile's orientation in a meaningful way.
func is_rotatable(cell: int) -> bool:
	if active[cell] == 0 or locked[cell] == 1:
		return false
	if link_of.size() > 0 and link_of[cell] >= 0:
		for member in link_groups[link_of[cell]]:
			if period_of(member) > 1:
				return true
		return false
	return period_of(cell) > 1


func portal_count() -> int:
	return portal_pairs.size() / 2


func active_count() -> int:
	var count := 0
	for c in topology.cell_count:
		count += active[c]
	return count


## Number of tiles that are rotatable (counted once per link group).
func rotatable_count() -> int:
	var count := 0
	var seen_groups := {}
	for c in topology.cell_count:
		if not is_rotatable(c):
			continue
		if link_of.size() > 0 and link_of[c] >= 0:
			if seen_groups.has(link_of[c]):
				continue
			seen_groups[link_of[c]] = true
		count += 1
	return count


func solution_rotations() -> PackedInt32Array:
	var rot := PackedInt32Array()
	rot.resize(topology.cell_count)
	return rot


func get_meta_value(key: String, default: Variant = null) -> Variant:
	return meta.get(key, default)


# --- Serialisation --------------------------------------------------------

func to_dict() -> Dictionary:
	var groups: Array = []
	for g in link_groups:
		groups.append(Array(g))
	return {
		"format": FORMAT_VERSION,
		"topology": topology.kind_name(),
		"width": topology.width,
		"height": topology.height,
		"mode": GameMode.id_of(mode),
		"active": Marshalls.raw_to_base64(active),
		"masks": Array(masks),
		"start_rot": Array(start_rot),
		"locked": Marshalls.raw_to_base64(locked),
		"cores": Array(cores),
		"portals": Array(portal_pairs),
		"links": groups,
		"unique": unique,
		"meta": meta.duplicate(true),
	}


static func from_dict(d: Dictionary) -> Puzzle:
	if int(d.get("format", 0)) != FORMAT_VERSION:
		return null
	var kind := TopologyFactory.kind_from_name(str(d.get("topology", "square")))
	var topo := TopologyFactory.create(kind, int(d.get("width", 1)), int(d.get("height", 1)))
	var p := Puzzle.create(topo)
	p.mode = GameMode.from_id(str(d.get("mode", "loop")))
	var act := Marshalls.base64_to_raw(str(d.get("active", "")))
	var lck := Marshalls.base64_to_raw(str(d.get("locked", "")))
	var msk := PackedInt32Array(d.get("masks", []))
	var rot := PackedInt32Array(d.get("start_rot", []))
	var n := topo.cell_count
	if act.size() != n or lck.size() != n or msk.size() != n or rot.size() != n:
		return null
	var full := topo.full_mask()
	for c in n:
		if msk[c] < 0 or msk[c] > full:
			return null
	p.active = act
	p.locked = lck
	p.masks = msk
	p.start_rot = rot
	p.cores = PackedInt32Array(d.get("cores", []))
	p.portal_pairs = PackedInt32Array(d.get("portals", []))
	for c in p.cores:
		if c < 0 or c >= n:
			return null
	for c in p.portal_pairs:
		if c < 0 or c >= n:
			return null
	var links: Array = d.get("links", [])
	for g in links:
		var group := PackedInt32Array(g)
		for c in group:
			if c < 0 or c >= n:
				return null
		p.link_groups.append(group)
	p.unique = bool(d.get("unique", false))
	var m: Variant = d.get("meta", {})
	p.meta = (m as Dictionary).duplicate(true) if m is Dictionary else {}
	p.finalize()
	return p
