class_name JsonUtil
extends RefCounted
## Quiet JSON parsing for untrusted input (saves, caches, imports): returns
## null on malformed text instead of raising an engine error.


static func parse(text: String) -> Variant:
	if text.is_empty():
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data


static func parse_dict(text: String) -> Dictionary:
	var v: Variant = parse(text)
	return v if v is Dictionary else {}
