extends SceneTree

const MissionPort = preload("res://contracts/ports/mission_port.gd")
const NetworkPort = preload("res://contracts/ports/network_port.gd")
const ContentPort = preload("res://contracts/ports/content_port.gd")
const R = preload("res://contracts/result.gd")
const HASH := "abababababababababababababababababababababababababababababababab"
const LOCAL := {"protocol_version": 1, "content_api_version": 1, "content_hash": HASH}
const PROTOCOL := {"protocol_version": 1, "content_api_version": 1}
var failures: Array[String] = []


class NetworkProbe extends NetworkPort:
	var authentication_calls := 0
	var active := 0

	func _authenticate_and_open(identity: Dictionary) -> Dictionary:
		authentication_calls += 1
		if identity.get("ticket") != "fixture-ticket":
			return R.fail("Unauthorized", "identity")
		active += 1
		return R.ok(active)

	func receive_input(_connection: int, _msg: Dictionary) -> Dictionary: return R.fail("Unavailable")
	func receive_order(_connection: int, _order: Dictionary) -> Dictionary: return R.fail("Unavailable")
	func build_snapshot(_connection: int, _interest: Dictionary, _baseline: Variant) -> Dictionary: return R.fail("Unavailable")
	func apply_authoritative_snapshot(_snapshot: Dictionary) -> Dictionary: return R.fail("Unavailable")
	func query_history(_server_validated_tick: int, _limit: int) -> Dictionary: return R.fail("Unavailable")
	func close_connection(_id: int, _reason: String) -> void: pass


class ContentProbe extends ContentPort:
	var calls := 0

	func _register_trusted_extension(_key: String, _implementation: Variant) -> Dictionary:
		calls += 1
		return R.ok(null)

	func scan_packages(_paths: Array) -> Array: return []
	func resolve_packages(_selection: Array, _game_api: int) -> Dictionary: return R.fail("Unavailable")
	func compile(_order: Array, _overrides: Dictionary) -> Dictionary: return R.fail("Unavailable")
	func validate_package(_package: Dictionary) -> Dictionary: return R.fail("Unavailable")
	func check_save_or_network_compatibility(_manifest: Dictionary, _compiled: Dictionary) -> Dictionary: return R.fail("Unavailable")


func expect(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
		printerr("FAIL ", label)


func rejected(receipt: Dictionary, code: String, field: String) -> bool:
	var error: Dictionary = receipt.get("error", {})
	return receipt.get("ok") == false and error.get("code") == code and error.get("field") == field


func test_handshake() -> bool:
	var local: Dictionary = LOCAL.duplicate()
	var net := NetworkProbe.new(local)
	local["protocol_version"] = 2
	var identity := {"ticket": "fixture-ticket"}
	for field: String in ["protocol_version", "content_api_version", "content_hash"]:
		var versions: Dictionary = PROTOCOL.duplicate()
		var digest := HASH
		if field == "content_hash":
			digest = "0".repeat(64)
		else:
			versions[field] = 2
		var result := net.handshake(identity, versions, digest)
		expect(rejected(result, "StaleVersion", field), "T-CON-02 mismatch " + field)
		expect(result.get("error", {}).get("detail") == LOCAL, "T-CON-02 required versions " + field)
		expect(not versions.has("content_hash"), "offer is immutable")
	expect(rejected(net.handshake(identity, {"protocol_version": true, "content_api_version": 1}, HASH),
			"InvalidArgument", "Handshake.protocol_version"), "boolean version")
	expect(rejected(net.handshake(identity, LOCAL, HASH), "InvalidArgument", "content_hash"), "ambiguous hash")
	expect(net.authentication_calls == 0 and net.active == 0, "incompatible peer never admitted")
	expect(rejected(net.handshake({}, PROTOCOL, HASH), "Unauthorized", "identity"), "identity rejected by backend")
	expect(net.active == 0, "no connection after denied identity")
	var accepted := net.handshake(identity, PROTOCOL, HASH)
	expect(accepted.ok and accepted.value == 1 and net.active == 1, "admitted matching peer")
	return true


func test_ports() -> bool:
	expect(MissionPort.VERSION == 1 and NetworkPort.VERSION == 1 and ContentPort.VERSION == 1, "v1 surfaces")
	var mission_script: Script = MissionPort
	var methods: Array = mission_script.get_script_method_list().map(func(m: Dictionary): return m.name)
	for method: String in ["prepare", "step_fixed", "request_end", "finalize", "dispose"]:
		expect(method in methods, "MissionPort." + method)
	var content := ContentProbe.new()
	var handler := func(): return null
	expect(rejected(content.register_extension("rule", handler, false), "Unauthorized", "trust"), "untrusted extension")
	expect(rejected(content.register_extension("", handler, true), "InvalidArgument", "extension"), "empty key")
	expect(rejected(content.register_extension("rule", null, true), "InvalidArgument", "extension"), "missing extension")
	expect(content.calls == 0, "rejected registrations do not reach registry")
	expect(content.register_extension("rule", handler, true).ok and content.calls == 1, "trusted registration")
	return true


func _initialize() -> void:
	expect(test_handshake(), "handshake suite completed")
	expect(test_ports(), "port suite completed")
	if failures.is_empty():
		print("PASS T-CON-02")
		print("PASS P1-PORTS-V1")
	quit(0 if failures.is_empty() else 1)
