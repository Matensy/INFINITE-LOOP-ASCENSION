class_name TopologyFactory
extends RefCounted
## Creates topologies by kind. Kept separate from Topology to avoid cyclic
## script references between the base class and its implementations.


static func create(kind: int, w: int, h: int) -> Topology:
	if kind == Topology.Kind.HEX:
		return HexTopology.new(w, h)
	return SquareTopology.new(w, h)


static func kind_from_name(name: String) -> int:
	return Topology.Kind.HEX if name == "hex" else Topology.Kind.SQUARE
