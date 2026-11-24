@abstract
extends RefCounted
## The transport authenticates identity and allocates a connection only after compatibility passes.
const VERSION := 1
const Schema = preload("res://contracts/schema.gd")
const Result = preload("res://contracts/result.gd")

var _local_compatibility: Dictionary


func _init(local_compatibility: Dictionary) -> void:
	_local_compatibility = local_compatibility.duplicate(true)


func handshake(identity: Dictionary, protocol: Dictionary, content_hash: String) -> Dictionary:
	# The hash is a separate argument, so a second copy in the protocol is ambiguous.
	if protocol.has("content_hash"):
		return Result.fail("InvalidArgument", "content_hash")
	var remote := protocol.duplicate(true)
	remote["content_hash"] = content_hash
	var compatible: Dictionary = Schema.check_compatible(_local_compatibility, remote)
	if not compatible.ok:
		return compatible
	return _authenticate_and_open(identity)


@abstract func _authenticate_and_open(identity: Dictionary) -> Dictionary
@abstract func receive_input(connection: int, msg: Dictionary) -> Dictionary
@abstract func receive_order(connection: int, order: Dictionary) -> Dictionary
@abstract func build_snapshot(connection: int, interest: Dictionary, baseline: Variant) -> Dictionary
@abstract func apply_authoritative_snapshot(snapshot: Dictionary) -> Dictionary
@abstract func query_history(server_validated_tick: int, limit: int) -> Dictionary
@abstract func close_connection(id: int, reason: String) -> void
