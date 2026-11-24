extends SceneTree

const Compiler = preload("res://infrastructure/content/compiler.gd")
const Adapter = preload("res://infrastructure/engine/adapter.gd")
const FIELD := "res://content/base/field"
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, description: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL field assets ",description)

func _rig(asset: String, definition: Dictionary) -> void:
	var path := FIELD.path_join(definition.file)
	check(FileAccess.get_sha256(path)==definition.sha256,"source digest "+asset)
	var packed := load(path) as PackedScene
	if packed == null:
		check(false,"imported scene "+path)
		return
	var model := packed.instantiate()
	root.add_child(model)
	var skeleton := model.find_children("*","Skeleton3D",true,false)
	var players := model.find_children("*","AnimationPlayer",true,false)
	check(skeleton.size()==1 and players.size()==1,"rig and animation player "+asset)
	if skeleton.size()!=1 or players.size()!=1:
		model.free()
		return
	var rig: Skeleton3D = skeleton[0]
	var player: AnimationPlayer = players[0]
	var skinned := 0
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		if mesh.skin!=null and mesh.mesh!=null:
			skinned += 1
	var motion := "Gallop" if asset=="horse" else "Run"
	check(rig.get_bone_count()==(50 if asset=="horse" else 22) and skinned>0,"skin "+asset)
	for clip in ["Idle","Walk",motion]:
		check(player.has_animation(clip),"missing "+clip)
	if player.has_animation(motion):
		player.play(motion)
		player.advance(0.01)
		var previous := []
		for i in rig.get_bone_count():
			previous.append(rig.get_bone_pose(i))
		player.advance(0.22)
		var moved := 0
		for i in rig.get_bone_count():
			if not rig.get_bone_pose(i).is_equal_approx(previous[i]):
				moved += 1
		check(moved>=3,"actual animated bones "+asset)
		print("FIELD_RIG ",asset," bones=",rig.get_bone_count()," meshes=",skinned," moving=",moved)
	model.free()

func run() -> void:
	var service := Compiler.new()
	var paths := [Compiler.BASE_PACKAGE,FIELD]
	var compiled := service.compile(service.scan_packages(paths),{})
	check(compiled.ok,"official content compiler "+str(compiled.get("error",{})))
	if not compiled.ok:
		quit(1)
		return
	paths.reverse()
	var cold := Compiler.new()
	var again := cold.compile(cold.scan_packages(paths),{})
	check(again.ok and again.value.hash==compiled.value.hash,"stable content digest")
	var registry: RefCounted = compiled.value.registry
	var spec: Dictionary = registry.get_definition("field:scene/river_plain","scene").value
	check(registry.get_definition("field:ruleset/field_battle","ruleset").value.mode=="field","compiled rule")
	for role in ["infantry","archer","cavalry"]:
		var troop: Dictionary = registry.get_definition("field:troop/"+role,"troop")
		check(troop.ok and troop.value.role==role and FileAccess.file_exists(FIELD.path_join(troop.value.metadata.model)),"troop model "+role)
	var assets: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIELD+"/assets.json"))
	for key in ["general","spear_soldier","crossbowman","horse"]:
		_rig(key,assets[key])
	var engine := Adapter.new(root,true)
	var token := engine.open_scope("asset-field")
	var loaded := engine.load_scene({"id":spec.id,"simulation_scene":spec.metadata.simulation_scene},token.value)
	check(loaded.ok,"real field scene")
	var reachable := false
	for frame in 90:
		await physics_frame
		var synced := engine.sync_navigation("asset-field")
		if synced.ok and synced.value.status=="applied":
			var path := engine.query_path_batch([{"from":[-52000,0,0],"to":[52000,0,0]}],synced.value.applied_revision,"asset-field")
			if path.ok and path.value[0].reachable:
				reachable = true
				break
	check(reachable,"field rally points connected")
	engine.release_scope("asset-field")
	check(engine.counts().scopes==0,"released field")
	print("FIELD_CONTENT hash=",compiled.value.hash)
	print("P2-FIELD-ASSETS ", "PASS" if failures==0 else "FAIL"," failures=",failures)
	quit(0 if failures==0 else 1)
