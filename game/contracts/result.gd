extends RefCounted

static func ok(value: Variant = null) -> Dictionary:
	return {"ok": true, "value": value}

static func map_error(code: String, _args: Dictionary = {}) -> String:
	return "error." + code.to_snake_case()

static func fail(code: String, field: String = "") -> Dictionary:
	return {"ok": false, "error": {"code": code, "field": field, "detail": null,
		"message_key": map_error(code), "retryable": code == "Unavailable"}}
