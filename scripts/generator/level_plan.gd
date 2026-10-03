class_name LevelPlan
extends RefCounted
## The multidimensional difficulty vector chosen for one puzzle. Produced by
## LevelPlanner, consumed by the generator layers.

var target: float = 5.0
var mode: int = GameMode.LOOP
var topology: int = Topology.Kind.SQUARE
var shape: int = BoardShapes.Shape.RECT
var width: int = 3
var height: int = 3
## LOOP / DARK: probability of an edge carrying a connector.
## CORE / MULTI: fraction of active cells covered by the network.
var density: float = 0.6
## Growing-tree randomness: 0 = long corridors, 1 = bushy networks.
var branching: float = 0.5
var cores: int = 0
var portals: int = 0
var link_groups: int = 0
var link_size: int = 2
## Locked helper tiles (shown already solved).
var anchors: int = 0
var require_unique: bool = false
var event: String = ""
var boss: bool = false
var theme: String = ""
var max_attempts: int = 8
var tolerance: float = 0.18
var node_limit: int = 6000


func duplicate_plan() -> LevelPlan:
	var p := LevelPlan.new()
	p.target = target
	p.mode = mode
	p.topology = topology
	p.shape = shape
	p.width = width
	p.height = height
	p.density = density
	p.branching = branching
	p.cores = cores
	p.portals = portals
	p.link_groups = link_groups
	p.link_size = link_size
	p.anchors = anchors
	p.require_unique = require_unique
	p.event = event
	p.boss = boss
	p.theme = theme
	p.max_attempts = max_attempts
	p.tolerance = tolerance
	p.node_limit = node_limit
	return p


func to_dict() -> Dictionary:
	return {
		"target": snappedf(target, 0.01),
		"mode": GameMode.id_of(mode),
		"topology": "hex" if topology == Topology.Kind.HEX else "square",
		"shape": BoardShapes.shape_name(shape),
		"width": width, "height": height,
		"density": snappedf(density, 0.001), "branching": snappedf(branching, 0.001),
		"cores": cores, "portals": portals,
		"link_groups": link_groups, "link_size": link_size,
		"anchors": anchors, "require_unique": require_unique,
		"event": event, "boss": boss, "theme": theme,
	}
