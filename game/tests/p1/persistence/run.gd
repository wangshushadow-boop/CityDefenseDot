extends SceneTree

const Store = preload("res://infrastructure/persistence/save_service.gd")
const C = preload("res://contracts/canonical.gd")
const Registry = preload("res://shared/definitions/registry.gd")
const F = preload("res://tests/p1/persistence/worker.gd")
var errors := 0
var save_root: String
var launches := 0

func check(pass_test: bool, label: String) -> void:
	if not pass_test:
		printerr("FAIL ",label)
		errors += 1

func run_child(slot: String, action: String, value: String = "") -> void:
	launches += 1
	var output := []
	var status := OS.execute(OS.get_executable_path(),["--headless","--quit-after","10","--path",ProjectSettings.globalize_path("res://"),
		"--log-file",save_root.path_join("child-%d.log"%launches),"--script","res://tests/p1/persistence/worker.gd",
		"--",save_root,slot,action,value],output,true)
	if action=="crash":
		var hit := save_root.path_join(slot+"-"+value+".hit")
		check(FileAccess.file_exists(hit) and FileAccess.get_file_as_string(hit).strip_edges()==value and not str(output).contains("Did not reach"),"crash boundary "+value+" rc="+str(status))
	else:
		check(status==0 and str(output).contains("PERSIST_WORKER "+action+" PASS"),slot+" "+action+" "+str(output))

func wait_files(prefix: String) -> bool:
	var deadline := Time.get_ticks_msec()+12000
	while Time.get_ticks_msec()<deadline:
		if FileAccess.file_exists(save_root.path_join(prefix+"1")) and FileAccess.file_exists(save_root.path_join(prefix+"2")):
			return true
		OS.delay_msec(5)
	return false

func race(store: RefCounted) -> void:
	var initial: Dictionary = store.save_game("race",F.state(0))
	check(initial.ok,"race seed")
	if not initial.ok:
		return
	for i in ["1","2"]:
		var pid := OS.create_process(OS.get_executable_path(),["--headless","--quit-after","10","--path",ProjectSettings.globalize_path("res://"),
			"--log-file",save_root.path_join("race-"+i+".log"),"--script","res://tests/p1/persistence/worker.gd",
			"--",save_root,"race","race",initial.value.commit_id,i])
		check(pid>0,"launch contender")
		launches+=1
	check(wait_files("ready-"),"both writers ready")
	var flag:=FileAccess.open(save_root.path_join("race.go"),FileAccess.WRITE)
	flag.close()
	if not wait_files("done-"):
		check(false,"race timeout")
		return
	var outcomes := []
	for i in ["1","2"]:
		outcomes.append(FileAccess.get_file_as_string(save_root.path_join("done-"+i)))
	check(outcomes.count("ok")==1 and (outcomes.has("Unavailable") or outcomes.has("StaleVersion")),"single winning writer "+str(outcomes))
	var restored: Dictionary = store.load_game("race",F.CONTENT)
	check(restored.ok and restored.value==F.state(outcomes.find("ok")+1),"checksum and state of winning writer")
	print("PERSIST_RACE ",outcomes)

func print_group(label: String, start: int) -> void:
	print(label," PASS" if errors==start else " FAIL")

func _initialize() -> void:
	save_root=ProjectSettings.globalize_path("user://p1-persist-"+Crypto.new().generate_random_bytes(9).hex_encode())
	check(DirAccess.make_dir_recursive_absolute(save_root)==OK,"isolated save_root")
	var store := Store.new(save_root)
	var start := errors
	for point in ["before_write","partial_world","after_backup","before_marker","after_marker"]:
		run_child(point,"seed")
		run_child(point,"crash",point)
		var visible := 1 if point=="after_marker" else 0
		run_child(point,"read",str(visible))
		run_child(point,"retry")
		run_child(point,"read","1")
	var rejected := store.commit_critical("after_marker",F.state(2),"battle-A")
	check(not rejected.ok and rejected.error.code=="Conflict","different snapshot with identical result ID")
	var dir := save_root.path_join("after_marker")
	var previous := store.recover("after_marker")
	var file := FileAccess.open(dir.path_join("world.bin"),FileAccess.WRITE)
	file.store_buffer("broken".to_utf8_buffer())
	file.close()
	var restored := store.recover("after_marker")
	check(previous.ok and restored.ok and restored.value.source=="backup" and restored.value.snapshot==F.state(0),"corruption fallback to previous checksum")
	check(store.commit_critical("after_marker",F.state(1),"battle-A").ok,"retry from valid backup")
	check(store.recover("after_marker").value.snapshot==F.state(1),"recovered reward exactly once")
	var base := store.save_game("concurrent",F.state(0))
	check(base.ok,"initial commit for competing callers")
	var newer := store.save_game("concurrent",F.state(1),"manual",base.value.commit_id)
	check(newer.ok and not store.save_game("concurrent",F.state(2),"manual",base.value.commit_id).ok,"reject stale commit token")
	check(not store.save_game("concurrent",F.state(0)).ok,"reject stale world revision")
	var unicode_result := store.commit_critical("concurrent",F.state(2),"胜利/一 %")
	check(unicode_result.ok and store.commit_critical("concurrent",F.state(2),"胜利/一 %",base.value.commit_id).value==unicode_result.value,"Unicode result ID retry precedes expected revision")
	check(store.recover("concurrent").value.applied_results.has("胜利/一 %"),"Unicode ledger restored as domain IDs")
	race(store)
	check(store.save_game("marker",F.state(0)).ok and store.save_game("marker",F.state(1)).ok,"two committed generations")
	var marker_path := save_root.path_join("marker/manifest.json")
	var original: Dictionary = C.decode(FileAccess.get_file_as_bytes(marker_path)).value
	for damaged in ["checksum","commit_id","schema_version"]:
		var changed := original.duplicate()
		if damaged=="checksum":
			changed.erase("checksum")
		elif damaged=="commit_id":
			changed.commit_id="bad"
		else:
			changed.schema_version=true
		var corrupt_bytes: PackedByteArray = C.encode(changed).value
		check(Store._save_bytes(marker_path,corrupt_bytes).ok,"write damaged marker")
		var fallback := Store.new(save_root).recover("marker")
		check(fallback.ok and fallback.value.source=="backup" and fallback.value.snapshot==F.state(0),"known invalid "+damaged+" restores backup")
		check(FileAccess.get_file_as_bytes(marker_path)==corrupt_bytes,"recover preserves damaged evidence")
	for unknown in ["version","field"]:
		var changed := original.duplicate()
		if unknown=="version":
			changed.schema_version=99
		else:
			changed["future_required"]=true
		var incompatible: PackedByteArray = C.encode(changed).value
		check(Store._save_bytes(marker_path,incompatible).ok,"write incompatible marker")
		var stopped := Store.new(save_root).recover("marker")
		check(not stopped.ok and stopped.error.code=="StaleVersion" and FileAccess.get_file_as_bytes(marker_path)==incompatible,"preserve incompatible primary "+unknown)
	print_group("T-PERSIST-02",start)
	start=errors
	var snap := F.state(7)
	var saved := store.save_game("multiA",snap,"manual")
	check(saved.ok and Store.new(save_root).load_game("multiA",F.CONTENT).value==snap,"canonical multi-year/RNG fixture")
	check(store.save_game("multiB",F.state(9)).ok and store.load_game("multiB",F.CONTENT).value!=snap,"independent second slot")
	check(not store.save_game("../bad",snap).ok,"reject slot escape")
	check(store.write_prebattle_checkpoint("checkpoint","encounter/b48883c0-79fb-4cd3-96fe-43bb44dfddbb",snap).ok,"safe-point checkpoint")
	print_group("T-PERSIST-01_SLICE",start)
	start=errors
	dir=save_root.path_join("v0")
	DirAccess.make_dir_recursive_absolute(dir)
	var v0 := C.encode({"schema_version":0,"minutes":24}).value as PackedByteArray
	var legacy := {"schema_version":0,"game_version":"0","world_id":"world-1","game_minute":24,"commit_id":"legacy",
		"summary":{},"content_packages":F.CONTENT.content_packages,"content_hash":F.HASH,"checksum":Store._hash(v0)}
	Store._save_bytes(dir.path_join("world.bin"),v0)
	var meta: PackedByteArray = C.encode(legacy).value
	Store._save_bytes(dir.path_join("manifest.json"),meta)
	var migrated := store.load_game("v0",F.CONTENT)
	check(migrated.ok and migrated.value.game_minute==24 and migrated.value.schema_version==1 and not migrated.value.has("minutes"),"v0 plain migration")
	check(FileAccess.get_file_as_bytes(dir.path_join("world.bin"))==v0 and FileAccess.get_file_as_bytes(dir.path_join("manifest.json"))==meta,"old files byte identical")
	check(not store.load_game("v0",{"content_hash":F.HASH,"content_packages":[]}).ok,"missing package")
	check(not store.load_game("v0",{"content_hash":"00".repeat(32),"content_packages":F.CONTENT.content_packages}).ok,"content mismatch")
	check(not Store.migrate({"schema_version":0,"minutes":0,"critical":1},0,1).ok,"unknown legacy field")
	legacy.schema_version=2
	Store._save_bytes(dir.path_join("manifest.json"),C.encode(legacy).value)
	var future := store.load_game("v0",F.CONTENT)
	check(not future.ok and future.error.code=="StaleVersion" and FileAccess.get_file_as_bytes(dir.path_join("world.bin"))==v0,"future schema refused")
	for bad_version in [true,0.5,"0",null,-1]:
		check(not Store.migrate({"schema_version":0,"minutes":1},bad_version,1).ok,"strict source version")
		check(not Store.migrate({"schema_version":0,"minutes":1},0,bad_version).ok,"strict target version")
	var part := {"id":"base:part/grip","schema_version":1,"source_package":"base"}
	var item := {"id":"world:item/cane","schema_version":1,"source_package":"base","category":"armor",
		"base_value":17,"weight":1,"quality_policy":"standard","slot_tags":[],"asset_ref":"base/cane",
		"part_ids":[part.id],"rule_snapshot":{"quality":80}}
	var crafted := F.state(2)
	crafted["dynamic_definitions"]=[item]
	crafted.repositories.inventory["item_ref"]=item.id
	check(store.save_game("crafted",crafted).ok,"store dynamic item")
	var from_disk := Store.new(save_root).load_game("crafted",F.CONTENT)
	var registry := Registry.new()
	var overlay := {}
	check(registry.build([part]).ok and from_disk.ok,"load definitions before instance references")
	for definition in from_disk.value.dynamic_definitions:
		var valid := registry.validate_dynamic_definition(definition,overlay)
		check(valid.ok,"restored dynamic definition resolves installed part")
		if valid.ok: overlay[definition.id]=definition
	check(overlay.has(from_disk.value.repositories.inventory.item_ref),"restored instance resolves dynamic ID")
	print_group("T-PERSIST-03_SLICE",start)
	print("T-PERSIST-04 NOT_RUN (requires real 50 Mission transitions)")
	print("PERSIST_CHECKS errors=",errors," child_processes=",launches)
	quit(0 if errors==0 else 1)
