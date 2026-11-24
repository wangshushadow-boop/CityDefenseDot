extends RefCounted
## Version 1 xorshift64. Store all 64 state bits as the ADR-012 hexadecimal value.
const R = preload("res://contracts/result.gd")
const Values = preload("res://contracts/values.gd")
const MASK := 0xffffffff

var _state: int
var _active := true

func _init(initial: String) -> void:
	_state = _from_hex(initial)
	if _state == 0:
		_state = 1

static func _from_hex(word: String) -> int:
	return (word.left(8).hex_to_int() << 32) | word.right(8).hex_to_int()

func next_u32() -> int:
	if not _active:
		return -1
	var value := _state
	value ^= value << 13
	value ^= (value >> 7) & 0x01ffffffffffffff
	value ^= value << 17
	_state = value
	return (value >> 32) & MASK

func snapshot() -> Dictionary:
	if not _active:
		return {}
	return {"algorithm_version": 1, "state": "%08x%08x" % [(_state >> 32) & MASK, _state & MASK]}

func restore(saved: Dictionary) -> Dictionary:
	if not _active:
		return R.fail("InvalidState","stream")
	if not Values.integer(saved.get("algorithm_version"), 1, 1):
		return R.fail("StaleVersion", "algorithm_version")
	if not Values.hex(saved.get("state"), 16):
		return R.fail("InvalidArgument", "state")
	var restored := _from_hex(saved.state)
	if restored == 0:
		return R.fail("InvalidArgument", "state")
	_state = restored
	return R.ok()

func retire() -> void:
	_active = false
