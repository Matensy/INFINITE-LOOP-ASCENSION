class_name RuleSet
extends RefCounted
## Defines what a "solved" board means for one mode.
##
## Rules are split into a *local* edge relation (used by the solver for
## constraint propagation) and an optional *global* check (connectivity,
## cores, ...). New mechanics plug in by subclassing and registering in
## RuleSet.for_mode().

## Both sides of an edge must agree: either both have a connector or none.
const RELATION_EQUAL := 0
## Two connectors may never face each other.
const RELATION_EXCLUSIVE := 1

## Rule sets are stateless and cheap, so a fresh instance is returned each
## call (safe to use from the background generator thread).
static func for_mode(mode: int) -> RuleSet:
	match mode:
		GameMode.CORE:
			return CoreRules.new()
		GameMode.MULTI:
			return MultiCoreRules.new()
		GameMode.DARK:
			return DarkRules.new()
	return LoopRules.new()


func relation() -> int:
	return RELATION_EQUAL


## Connectors facing the board edge or a void cell are never allowed.
func boundary_allows_connector() -> bool:
	return false


## True when the mode needs a forest of trees, each holding one core.
func requires_forest() -> bool:
	return false


## True when energy propagation from cores is meaningful for rendering.
func uses_power() -> bool:
	return false


func edge_ok(a_has: bool, b_has: bool) -> bool:
	if relation() == RELATION_EXCLUSIVE:
		return not (a_has and b_has)
	return a_has == b_has


## Global constraints beyond local edges. `masks` are the current masks.
func check_global(_puzzle: Puzzle, _masks: PackedInt32Array) -> bool:
	return true
