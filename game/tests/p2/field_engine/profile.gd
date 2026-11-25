extends SceneTree

const Adapter = preload("res://infrastructure/engine/adapter.gd")
const PLAIN := {"id":"field:scene/river_plain","simulation_scene":"res://content/base/field/river_plain.tscn"}
var engine: Adapter

func _initialize() -> void:
	run.call_deferred()

func sample(count: int) -> bool:
	var scope := "field-profile-%d" % count
	var opened := engine.open_scope(scope)
	if not opened.ok or not engine.load_scene(PLAIN,opened.value).ok:
		return false
	await physics_frame
	await physics_frame
	var rows := []
	for index in count:
		var x := float(index % 50)*1.45-36
		var z := float(floori(float(index)/50))*1.45-15
		rows.append({"handle":{"index":index,"generation":1},"position":Vector3(x,0,z),
			"team_key":int(index >= floori(count*0.5)),"type":"mount" if index%6==0 else "human","shield":index%6==2})
	if not engine.field_stage_bodies(scope,rows).ok or not engine.field_commit_bodies(scope).ok:
		return false
	var times := PackedInt64Array()
	for phase in ["stationary","moving"]:
		times.clear()
		for tick in 132:
			if phase=="moving":
				for row in rows:
					row.position.x += 0.025
			var started := Time.get_ticks_usec()
			if not engine.field_stage_bodies(scope,rows).ok or not engine.field_commit_bodies(scope).ok:
				return false
			if tick >= 12:
				times.append(Time.get_ticks_usec()-started)
		times.sort()
		print("FIELD_BODY_PROFILE bodies=",count," mode=",phase," ticks=",times.size()," median_us=",times[59]," p95_us=",times[113]," max_us=",times[-1])
	var last: Dictionary = rows[-1]
	var at: Vector3 = last.position*1000
	var cast := {"from":[roundi(at.x-600),1100,roundi(at.z)],"to":[roundi(at.x+600),1100,roundi(at.z)]}
	var contacts := engine.field_sweep(scope,[cast],265)
	engine.release_scope(scope)
	return contacts.ok and contacts.value.any(func(hit): return hit.target==last.handle)

func run() -> void:
	engine = Adapter.new(root)
	var ok: bool = await sample(500) and await sample(1000)
	print("FIELD_BODY_PROFILE ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
