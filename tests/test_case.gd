class_name TestCase
extends RefCounted
## Minimal assertion base class for the headless test runner. Test scripts
## extend this and define methods named `test_*`.

var failures: PackedStringArray = PackedStringArray()
var assertions: int = 0


func before_each() -> void:
	pass


func after_each() -> void:
	pass


func fail(message: String) -> void:
	failures.append(message)


func assert_true(condition: bool, message: String = "expected true") -> void:
	assertions += 1
	if not condition:
		fail(message)


func assert_false(condition: bool, message: String = "expected false") -> void:
	assertions += 1
	if condition:
		fail(message)


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	assertions += 1
	if typeof(actual) != typeof(expected) and not (_is_number(actual) and _is_number(expected)):
		fail("%s expected %s (%s) got %s (%s)" % [message, str(expected), type_string(typeof(expected)), str(actual), type_string(typeof(actual))])
	elif actual != expected:
		fail("%s expected %s got %s" % [message, str(expected), str(actual)])


func assert_ne(actual: Variant, unexpected: Variant, message: String = "") -> void:
	assertions += 1
	if actual == unexpected:
		fail("%s value should differ from %s" % [message, str(unexpected)])


func assert_between(value: float, lo: float, hi: float, message: String = "") -> void:
	assertions += 1
	if value < lo or value > hi:
		fail("%s %s not in [%s, %s]" % [message, str(value), str(lo), str(hi)])


func assert_not_null(value: Variant, message: String = "expected non-null") -> void:
	assertions += 1
	if value == null:
		fail(message)


func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT
