extends RefCounted
## APP supplies a safe-point snapshot. A slot has one committed manifest and one
## previous valid generation. No Godot object or domain callback is persisted.
const C = preload("res://contracts/canonical.gd")
const R = preload("res://contracts/result.gd")
const S = preload("res://contracts/schema.gd")
const V = preload("res://contracts/values.gd")
const Platform = preload("res://infrastructure/persistence/atomic_windows.gd")
const META := ["schema_version","game_version","content_packages","content_hash","world_id","game_minute","commit_id","checksum","summary"]
const COMMON := ["world_id","game_minute","content_hash","content_packages"]

var _root: String
var fault_point := ""
var on_injected_fault: Callable

func _fault() -> Dictionary:
	if on_injected_fault.is_valid():
		on_injected_fault.call(fault_point)
	return R.fail("Unavailable","fault."+fault_point)

func _init(root: String = "user://saves") -> void:
	_root = ProjectSettings.globalize_path(root).simplify_path()

static func _slot_ok(slot: String) -> bool:
	if slot.is_empty() or slot.length() > 64:
		return false
	for letter in slot:
		if not letter in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":
			return false
	return slot.to_upper() not in ["CON","PRN","AUX","NUL","COM1","COM2","COM3","COM4","COM5","COM6","COM7","COM8","COM9","LPT1","LPT2","LPT3","LPT4","LPT5","LPT6","LPT7","LPT8","LPT9"]

static func _hash(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()

static func _bytes(path: String) -> Dictionary:
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null:
		return R.fail("Unavailable",path.get_file())
	var length := file.get_length()
	var data := file.get_buffer(length)
	file.close()
	if data.size() != length:
		return R.fail("Unavailable",path.get_file())
	return R.ok(data)

static func _save_bytes(path: String, bytes: PackedByteArray) -> Dictionary:
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null:
		return R.fail("Unavailable",path.get_file())
	var complete := file.store_buffer(bytes)
	file.flush()
	var error := file.get_error()
	file.close()
	if not complete or error != OK:
		return R.fail("Unavailable",path.get_file())
	var copy := _bytes(path)
	if not copy.ok or copy.value != bytes:
		return R.fail("Unavailable","verify."+path.get_file())
	return R.ok()

static func _shape(snapshot: Variant, require_current: bool = true) -> bool:
	return typeof(snapshot) == TYPE_DICTIONARY and typeof(snapshot.get("world_id"))==TYPE_STRING and not snapshot.world_id.is_empty() and V.integer(snapshot.get("game_minute")) and V.hex(snapshot.get("content_hash"),64) and C.is_json_array(snapshot.get("content_packages")) and (not snapshot.has("revision") or V.integer(snapshot.revision)) and (not require_current or not snapshot.has("schema_version") or V.integer(snapshot.schema_version,1,1))

static func _id_ok(id: String) -> bool:
	if id.is_empty() or not C.encode(id).ok:
		return false
	for i in id.length():
		var ch := id.unicode_at(i)
		if ch < 32 or (ch >= 127 and ch <= 159):
			return false
	return true

static func _valid_ledger(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	for key in value:
		var id: String = key.uri_decode()
		if not _id_ok(id) or id.uri_encode() != key:
			return false
		var fact: Variant = value[key]
		if typeof(fact)!=TYPE_DICTIONARY or fact.size()!=2 or not V.hex(fact.get("digest"),64) or not V.hex(fact.get("commit_id"),32):
			return false
	return true

static func migrate(data: Variant, from: Variant, to: Variant) -> Dictionary:
	if not V.integer(from) or not V.integer(to):
		return R.fail("InvalidArgument","schema_version")
	if from == 0 and to == 1:
		var encoded := C.encode(data)
		if not encoded.ok:
			return encoded
		return S.decode_value("SaveHeader",encoded.value,0)
	return R.fail("StaleVersion","schema_version")

static func _generation(dir: String) -> Dictionary:
	var marker := dir.path_join("manifest.json")
	if not FileAccess.file_exists(marker):
		return R.fail("NotFound","manifest.json")
	var raw := _bytes(marker)
	if not raw.ok:
		return raw
	var parsed := C.decode(raw.value)
	if not parsed.ok or typeof(parsed.value)!=TYPE_DICTIONARY:
		return R.fail("InvalidState","manifest.json")
	var m: Dictionary = parsed.value
	if not V.integer(m.get("schema_version")):
		return R.fail("InvalidState","manifest.schema_version")
	if m.schema_version > 1:
		return R.fail("StaleVersion","manifest.schema_version")
	for key in m:
		if key not in META:
			return R.fail("StaleVersion","manifest."+key)
	if not m.has_all(META):
		return R.fail("InvalidState","manifest.fields")
	var valid_id: bool = V.hex(m.commit_id,32) if m.schema_version==1 else (typeof(m.commit_id)==TYPE_STRING and not m.commit_id.is_empty())
	if not _shape(m,false) or typeof(m.game_version)!=TYPE_STRING or m.game_version.is_empty() or not valid_id or not V.hex(m.checksum,64) or typeof(m.summary)!=TYPE_DICTIONARY:
		return R.fail("InvalidState","manifest.fields")
	var world := _bytes(dir.path_join("world.bin"))
	if not world.ok or _hash(world.value)!=m.checksum:
		return R.fail("InvalidState","world.checksum")
	var decoded := C.decode(world.value)
	if not decoded.ok or typeof(decoded.value)!=TYPE_DICTIONARY:
		return R.fail("InvalidState","world.bin")
	var data: Dictionary = decoded.value
	var ledger := {}
	var snapshot: Dictionary
	if m.schema_version == 0:
		for key in data:
			if key not in ["schema_version","minutes"]:
				return R.fail("StaleVersion","world."+key)
		var next := migrate(data,0,1)
		if not next.ok:
			return R.fail("InvalidState","world.v0")
		snapshot=next.value.duplicate()
		for key in COMMON:
			if key!="game_minute":
				snapshot[key]=m[key]
	else:
		for key in data:
			if key not in ["snapshot","applied_results"]:
				return R.fail("StaleVersion","world."+key)
		if not data.has_all(["snapshot","applied_results"]):
			return R.fail("InvalidState","world.fields")
		if not _shape(data.snapshot) or not _valid_ledger(data.applied_results):
			return R.fail("InvalidState","world.fields")
		snapshot=data.snapshot
		for disk_key: String in data.applied_results:
			ledger[disk_key.uri_decode()]=data.applied_results[disk_key]
	for key in COMMON:
		if snapshot[key]!=m[key]:
			return R.fail("InvalidState","manifest."+key)
	return R.ok({"manifest":m,"snapshot":snapshot,"applied_results":ledger})

func recover(slot: String) -> Dictionary:
	if not _slot_ok(slot):
		return R.fail("InvalidArgument","slot")
	var dir := _root.path_join(slot)
	var current := _generation(dir)
	if current.ok:
		current.value["source"]="primary"
		return current
	if current.error.code not in ["NotFound","InvalidState"]:
		return current
	var backup := _generation(dir.path_join("backup"))
	if backup.ok:
		backup.value["source"]="backup"
		return backup
	return current if backup.error.code=="NotFound" else backup

func load_game(slot: String, installed_content: Dictionary) -> Dictionary:
	var recovered := recover(slot)
	if not recovered.ok:
		return recovered
	var manifest: Dictionary = recovered.value.manifest
	if installed_content.get("content_hash") != manifest.content_hash:
		return R.fail("StaleVersion","content_hash")
	if not C.is_json_array(installed_content.get("content_packages")) or installed_content.content_packages != manifest.content_packages:
		return R.fail("StaleVersion","content_packages")
	return R.ok(recovered.value.snapshot)

func save_game(slot: String, snapshot: Dictionary, reason: String = "manual", expected_commit_id: Variant = null) -> Dictionary:
	return _commit(slot,snapshot,{"reason":reason},"",expected_commit_id)

func write_prebattle_checkpoint(slot: String, encounter_id: String, snapshot: Dictionary, expected_commit_id: Variant = null) -> Dictionary:
	if not V.typed_id(encounter_id,"encounter"):
		return R.fail("InvalidArgument","encounter_id")
	return _commit(slot,snapshot,{"reason":"prebattle","encounter_id":encounter_id},"",expected_commit_id)

func commit_critical(slot: String, snapshot: Dictionary, applied_result_id: String, expected_commit_id: Variant = null) -> Dictionary:
	if not _id_ok(applied_result_id):
		return R.fail("InvalidArgument","applied_result_id")
	return _commit(slot,snapshot,{"reason":"critical"},applied_result_id,expected_commit_id)

func _commit(slot: String, snapshot: Dictionary, summary: Dictionary, result_id: String, expected_commit_id: Variant) -> Dictionary:
	if not _slot_ok(slot) or not _shape(snapshot) or (expected_commit_id!=null and typeof(expected_commit_id)!=TYPE_STRING):
		return R.fail("InvalidArgument","slot_or_snapshot")
	var digest := C.hash_value(snapshot)
	if not digest.ok:
		return digest
	var dir := _root.path_join(slot)
	if DirAccess.make_dir_recursive_absolute(dir)!=OK:
		return R.fail("Unavailable","slot")
	var primary_hash := _marker_hash(dir)
	var backup_hash := _marker_hash(dir.path_join("backup"))
	var previous := recover(slot)
	if not previous.ok and previous.error.code!="NotFound":
		return previous
	var ledger: Dictionary = previous.value.applied_results if previous.ok else {}
	if previous.ok and previous.value.manifest.world_id!=snapshot.world_id:
		return R.fail("Conflict","world_id")
	if result_id!="" and ledger.has(result_id):
		if ledger[result_id].digest!=digest.value:
			return R.fail("Conflict","applied_result_id")
		return R.ok({"commit_id":ledger[result_id].commit_id})
	var current_id: String = previous.value.manifest.commit_id if previous.ok else ""
	if expected_commit_id!=null and expected_commit_id!=current_id:
		return R.fail("StaleVersion","commit_id")
	if previous.ok and previous.value.snapshot.has("revision"):
		if not snapshot.has("revision") or snapshot.revision < previous.value.snapshot.revision:
			return R.fail("StaleVersion","revision")
		if snapshot.revision == previous.value.snapshot.revision and snapshot != previous.value.snapshot:
			return R.fail("Conflict","revision")
	var commit_id := Crypto.new().generate_random_bytes(16).hex_encode()
	if result_id!="":
		ledger[result_id]={"digest":digest.value,"commit_id":commit_id}
	var disk_ledger := {}
	for key: String in ledger:
		disk_ledger[key.uri_encode()]=ledger[key]
	var bytes := C.encode({"snapshot":snapshot,"applied_results":disk_ledger})
	if not bytes.ok:
		return bytes
	var manifest := {"schema_version":1,"game_version":"0.1","commit_id":commit_id,
		"checksum":_hash(bytes.value),"summary":summary}
	for key in COMMON:
		manifest[key]=snapshot[key]
	var encoded := C.encode(manifest)
	if not encoded.ok:
		return encoded
	if fault_point=="before_write":
		return _fault()
	var stage := dir.path_join(".pending-"+commit_id)
	if DirAccess.make_dir_absolute(stage)!=OK:
		return R.fail("Unavailable","staging")
	var outcome := _stage(dir,stage,bytes.value,encoded.value,primary_hash,backup_hash,previous)
	# These are exclusively this call's staging names. Live/backup files never
	# use this cleanup and uncommitted stages from interrupted processes are ignored.
	for name in ["world.bin","manifest.json","old-world.bin","old-manifest.json"]:
		var staged := stage.path_join(name)
		if FileAccess.file_exists(staged):
			DirAccess.remove_absolute(staged)
	DirAccess.remove_absolute(stage)
	return R.ok({"commit_id":commit_id}) if outcome.ok else outcome

static func _marker_hash(dir: String) -> String:
	var path := dir.path_join("manifest.json")
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""

func _stage(dir: String, stage: String, world: PackedByteArray, marker: PackedByteArray, primary_hash: String, backup_hash: String, previous: Dictionary) -> Dictionary:
	var payload := world.slice(0,world.size()/2) if fault_point=="partial_world" else world
	var wrote := _save_bytes(stage.path_join("world.bin"),payload)
	if not wrote.ok:
		return wrote
	if fault_point=="partial_world":
		return _fault()
	wrote = _save_bytes(stage.path_join("manifest.json"),marker)
	if not wrote.ok:
		return wrote
	var published := Platform.publish({"dir":dir,"stage":stage,"primary":primary_hash,"backup":backup_hash,
		"source":previous.value.source if previous.ok else "empty",
		"checksum":previous.value.manifest.checksum if previous.ok else "", "fault":fault_point})
	if not published.ok and published.error.field.begins_with("fault."):
		return _fault()
	return published
