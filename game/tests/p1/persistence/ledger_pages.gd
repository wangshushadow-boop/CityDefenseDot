extends SceneTree

const Store = preload("res://infrastructure/persistence/save_service.gd")
const C = preload("res://contracts/canonical.gd")

func _initialize() -> void:
	var facts := {}
	var fact := {"digest":"a".repeat(64),"commit_id":"b".repeat(32)}
	for n in 65537:
		facts["result:%d" % n] = fact
	var disk: Array = Store._ledger_to_disk(facts)
	var encoded := C.encode(disk)
	var bytes: int = encoded.value.size() if encoded.ok else 0
	var decoded := C.decode(encoded.value) if encoded.ok else encoded
	var restored := Store._ledger_from_disk(decoded.value) if decoded.ok else decoded
	var flat := Store._ledger_from_disk({"old%3Akey":fact})
	var good: bool = restored.ok and restored.value == facts and flat.ok and flat.value.has("old:key")
	good = good and not Store._ledger_from_disk([disk[0],disk[0]]).ok
	print("PERSIST_LEDGER_PAGES ", "PASS" if good else "FAIL", " facts=",facts.size()," pages=",disk.size()," bytes=",bytes)
	quit(0 if good else 1)
