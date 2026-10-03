class_name GameMode
extends RefCounted
## Puzzle rule modes. A mode defines how connectors must relate to each other
## (see RuleSet). Modifiers such as PERFECT (unique solution) or CHAOS (linked
## tiles) are puzzle properties layered on top of any mode.

enum { LOOP = 0, CORE = 1, MULTI = 2, DARK = 3 }

const COUNT := 4
const IDS: Array[String] = ["loop", "core", "multi", "dark"]


static func id_of(mode: int) -> String:
	return IDS[clampi(mode, 0, COUNT - 1)]


static func from_id(id: String) -> int:
	var idx := IDS.find(id)
	return maxi(idx, 0)


## Translation key of the short mode title (see data/i18n).
static func title_key(mode: int) -> String:
	return "MODE_" + id_of(mode).to_upper()


## Translation key of the one-line objective.
static func objective_key(mode: int) -> String:
	return "OBJECTIVE_" + id_of(mode).to_upper()


static func uses_cores(mode: int) -> bool:
	return mode == CORE or mode == MULTI
