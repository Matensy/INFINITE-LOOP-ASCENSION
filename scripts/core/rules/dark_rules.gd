class_name DarkRules
extends RuleSet
## DARK: the inverted goal. No two connectors may touch and no connector may
## point off the board. Every piece must end up isolated.


func relation() -> int:
	return RELATION_EXCLUSIVE
