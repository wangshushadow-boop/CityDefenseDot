extends SceneTree

const Compiler = preload("res://infrastructure/content/compiler.gd")
const Codec = preload("res://contracts/canonical.gd")
var errors := 0
var scratch: String
var files: Array[String] = []
var dirs: Array[String] = []
var service := Compiler.new()

func expect(value: bool, label: String) -> void:
	if not value:
		errors += 1
		printerr("FAIL ",label)

func put(path: String, data: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		expect(false,"fixture write " + path)
		return
	file.store_buffer(Codec.encode(data).value)
	file.close()
	if path not in files:
		files.append(path)

func create(id: String, source: Dictionary = {}) -> String:
	var root := scratch.path_join(id)
	DirAccess.make_dir_recursive_absolute(root)
	dirs.append(root)
	var manifest := {"id":id,"version":"1.0","game_api_version":1,"requires":[],"conflicts":[],"load_after":[],"entrypoints":{},"license":"Original QA fixture"}
	manifest.merge(source,true)
	put(root.path_join("manifest.json"),manifest)
	return root

func assemble(paths: Array, overrides: Dictionary = {}) -> Dictionary:
	var scanned := service.scan_packages(paths)
	var resolved := service.resolve_packages(scanned,1)
	if not resolved.ok:
		return resolved
	return service.compile(resolved.value,overrides)

func _rule() -> int:
	return 17

func _initialize() -> void:
	scratch = OS.get_cache_dir().path_join("recollection-content-" + str(OS.get_process_id()) + "-" + str(Time.get_ticks_usec()))
	DirAccess.make_dir_recursive_absolute(scratch)
	var before := errors
	var base := assemble([Compiler.BASE_PACKAGE])
	expect(base.ok,"real base compile " + str(base))
	if not base.ok:
		quit(1)
		return
	var common := {"requires":[{"id":"base","version":"1.0.0"}],"entrypoints":{"definitions":["defs.json"],"patches":["patch.json"]}}
	var mod := create("delta",common)
	put(mod.path_join("defs.json"),[{"id":"delta:culture/fen","schema_version":1,"name":"沼泽"}])
	put(mod.path_join("patch.json"),[{"def_id":"base:culture/river","path":["name"],"op":"replace","value":"水乡"}])
	expect(not service.register_extension("rule.fen",_rule,false).ok,"untrusted rejected")
	expect(service.register_extension("rule.fen",_rule,true).ok,"trusted host registration")
	var callback := service.get_extension("rule.fen")
	expect(callback.ok and callback.value.call() == 17,"public callback")
	expect(not service.register_extension("bogus.fen",_rule,true).ok and not service.register_extension("rule.fen",_rule,true).ok,"bad category / duplicate")
	var good := assemble([mod,Compiler.BASE_PACKAGE],{"battle_limit":250})
	expect(good.ok,"compile additional data")
	if not good.ok:
		quit(1)
		return
	var snapshot: Dictionary = good.value
	expect(snapshot.registry.get_definition("delta:culture/fen","culture").ok,"registry injected")
	expect(snapshot.registry.get_definition("base:culture/river").value.name == "水乡","patch took effect")
	expect(snapshot.config.battle_limit == 250 and snapshot.config_provenance.battle_limit == "session","config provenance")
	expect(snapshot.is_read_only() and snapshot.packages.is_read_only(),"immutable")
	print("T-INF-CONTENT-01-SLICE ","PASS" if before == errors else "FAIL")
	before = errors
	var a := create("a",{"requires":["b"]})
	var b := create("b",{"requires":["a"]})
	expect(not assemble([a,b]).ok,"dependency cycle")
	expect(not assemble([a]).ok,"missing dependency")
	var wrong := create("wrong",{"requires":[{"id":"base","version":"0"}]})
	expect(not assemble([wrong,Compiler.BASE_PACKAGE]).ok,"dependency version")
	var conflict := create("other",{"conflicts":["base"]})
	expect(not assemble([conflict,Compiler.BASE_PACKAGE]).ok,"declared conflict")
	var other := create("another",{"requires":["base"],"entrypoints":{"patches":["patch.json"]}})
	put(other.path_join("patch.json"),[{"def_id":"base:culture/river","path":["name"],"op":"replace","value":"冲突"}])
	var overlap := assemble([Compiler.BASE_PACKAGE,other,mod])
	expect(not overlap.ok and overlap.error.code == "Conflict" and overlap.error.detail[0] == "another","incompatible patches identify authors")
	var outside := create("outer",{"entrypoints":{"definitions":["../delta/defs.json"]}})
	expect(not assemble([outside]).ok,"directory escape")
	expect(not assemble([Compiler.BASE_PACKAGE],{"missing":1}).ok,"unknown config")
	expect(not service.check_save_or_network_compatibility({"game_api_version":1,"content_hash":"0".repeat(64)},snapshot).ok,"different content hash")
	expect(service.check_save_or_network_compatibility({"game_api_version":1,"packages":snapshot.packages,"content_hash":snapshot.hash},snapshot).ok,"compatible")
	print("T-INF-CONTENT-02 ","PASS" if before == errors else "FAIL")
	before = errors
	var again := assemble([Compiler.BASE_PACKAGE,mod],{"battle_limit":250})
	expect(again.ok and snapshot.hash == again.value.hash,"reproducible hash")
	expect(snapshot.hash != assemble([mod,Compiler.BASE_PACKAGE],{"battle_limit":100}).value.hash,"content-affecting config digest")
	var unlicensed := create("unlicensed",{"license":""})
	expect(not assemble([unlicensed]).ok,"license required")
	print("T-INF-CONTENT-03-SLICE ","PASS" if before == errors else "FAIL")
	before = errors
	var site := create("site",{"entrypoints":{"definitions":["scenes.json"],"resources":["map.scene.json"]}})
	var scene := {"id":"site:scene/yard","schema_version":1,"asset_ref":"map.scene.json","spawn_zones":["spawn"],"objectives":["goal"]}
	put(site.path_join("scenes.json"),[scene])
	put(site.path_join("map.scene.json"),{"markers":[{"id":"spawn","kind":"spawn","position_mm":[0,0,0]}]})
	var missing := assemble([site])
	expect(not missing.ok and missing.error.field == "site","undefined objective")
	put(site.path_join("map.scene.json"),{"markers":[{"id":"spawn","kind":"spawn","position_mm":[0,0,0]},{"id":"goal","kind":"objective","position_mm":[1,0,0]}]})
	expect(assemble([site]).ok,"marker repair")
	scene["spawn_zones"] = []
	put(site.path_join("scenes.json"),[scene])
	expect(not assemble([site]).ok,"spawns required")
	print("T-INF-CONTENT-04 ","PASS" if before == errors else "FAIL")
	print("P1-CONTENT errors=",errors," base_hash=",base.value.hash)
	for path in files:
		DirAccess.remove_absolute(path)
	for root in dirs:
		DirAccess.remove_absolute(root)
	DirAccess.remove_absolute(scratch)
	quit(0 if errors == 0 else 1)
