class_name ForestRules
extends RuleSet
## Shared logic for core based modes: all connectors matched and every
## network component holds exactly one core. Because the number of connectors
## is fixed by the pieces, this also forbids cycles (see docs/GENERATOR.md).


func requires_forest() -> bool:
	return true


func uses_power() -> bool:
	return true


func check_global(puzzle: Puzzle, masks: PackedInt32Array) -> bool:
	var comp := Connectivity.components(puzzle, masks)
	var cores_in := {}
	for c in puzzle.cores:
		var root := comp[c]
		var count: int = int(cores_in.get(root, 0)) + 1
		if count > 1:
			return false
		cores_in[root] = count
	for c in puzzle.cell_count():
		if puzzle.network_cell[c] == 1 and not cores_in.has(comp[c]):
			return false
	return true
