extends SceneTree

const Audio = preload("res://presentation/audio/ports/field_audio.gd")
const Combat = preload("res://mission/combat/ports/field_combat.gd")
const Formation = preload("res://mission/formation/ports/field_formation.gd")
const Mission = preload("res://mission/runtime/runtime.gd")
const Adapter = preload("res://infrastructure/engine/adapter.gd")
const Core = preload("res://core/runtime.gd")
const Targets = preload("res://tests/p2/audio/field_targets.gd")
const Canon = preload("res://contracts/canonical.gd")
const R = preload("res://contracts/result.gd")
const MID := "audio-battle"
var failures := 0
var adapter: Adapter
var pcm_peak := 0.0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL ",message)

func envelope(id: String, kind: String, payload: Dictionary, tick := 4) -> Dictionary:
	return {"scope_id":MID,"tick":tick,"revision":tick,"type":kind,"payload":payload,"event_id":id}

func targets(queries: Array, tick: int) -> Dictionary:
	var rows := adapter.query_sweep_batch(queries,{"scope_id":MID,"tick":tick})
	if not rows.ok:
		return rows
	var hits := []
	for row in rows.value:
		hits.append({"query_index":row.query_index,"fraction_ppm":row.fraction_ppm,"region":row.region,
			"target":{"index":row.entity_handle.to_int(),"generation":1}})
	return R.ok(hits)

func build_result(snapshot: Dictionary, outcome: Dictionary) -> Dictionary:
	var result := {"schema_version":1,"result_id":"audio-fixture-result","encounter_id":null,"mission_id":snapshot.mission_id,
		"reservation_revision":null,"outcome":outcome.outcome,"duration_ticks":snapshot.tick,"winner_team_keys":["allies"],
		"objective_results":[],"slot_outcomes":[],"loot_claims":[],"hero_outcomes":[],"siege_changes":null,"reward_intents":[],"stats":{}}
	result["integrity_hash"] = Canon.hash_value(result).value
	return R.ok(result)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var completed: bool = await exercise()
	check(completed,"completed all audio cases")
	print("P2-AUD-BATTLE-001 ", "PASS" if not failures else "FAIL", " errors=",failures)
	quit(1 if failures else 0)

func exercise() -> bool:
	TranslationServer.set_locale("zh_CN")
	var bus_count := AudioServer.bus_count
	var output := Audio.new()
	root.add_child(output)
	var path := "user://audio-test-%d.cfg"%Time.get_ticks_usec()
	check(output.open_scope(MID,12,path).ok,"open 12-source scope")
	var state := output.diagnostics()
	check(state.allocated==12 and AudioServer.bus_count==bus_count+6,"all mixer groups and source budget")
	for key in ["Voice","Effects","Music","Ambience","UI"]:
		check(AudioServer.get_bus_index(state.buses[key])>0,"actual audio server bus "+key)
	var voice_bus := AudioServer.get_bus_index(state.buses.Voice)
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 1.0
	AudioServer.add_bus_effect(voice_bus,capture)
	var listener := AudioListener3D.new()
	root.add_child(listener)
	listener.make_current()
	root.audio_listener_enable_3d = true
	adapter = Adapter.new(root,true)
	var mission := Mission.new(Core.new(),adapter,"audio-test",build_result,MID)
	var scene := {"id":"test:scene/audio","simulation_scene":"res://tests/p2/audio/field.tscn"}
	var rules := {"id":"test:ruleset/audio"}
	var spec := {"schema_version":1,"encounter_id":"encounter/b48883c0-79fb-4cd3-96fe-43bb44dfddbb",
		"reservation_revision":1,"mode":"custom","scene_def_id":scene.id,"ruleset_id":rules.id,"environment":{},
		"rng_seed":42,"sides":[],"reserved_sources":[],"battle_limit":500,"deployment_constraints":{},"siege_snapshot":null}
	check(mission.prepare(spec,scene,rules).ok,"real 500-person Mission")
	var combat := Combat.new()
	var poses := {}
	var start := []
	var release := []
	var roster := []
	for i in 500:
		var h: Dictionary = mission.allocate_entity(null,{}).value
		check(combat.enlist(h,{"team":0 if i<250 else 1,"role":"infantry"}).ok,"enlist actor")
		var pos := Targets.start_mm(i%250)
		if i<250:
			roster.append(h)
			var attack := {"actor_handle":h,"input_phase":"start","direction":"thrust","weapon_slot":0,"target_hint":null}
			start.append(attack)
			var fire := attack.duplicate()
			fire.input_phase = "release"
			release.append(fire)
		else:
			pos[0] += 1000
		poses[i] = {"position_mm":pos, "facing_ppm":[1000000,0,0]}
	check(mission.register_system("action",{"id":"combat","run":func(_v,b): return combat.step_field(b.source_tick,b.inputs,poses,targets)}).ok,"register combat authority")
	await physics_frame
	await physics_frame
	var confirmed := []
	for tick in range(1,5):
		var inputs: Array = start if tick==1 else (release if tick==4 else [])
		var step := mission.step_fixed(tick,inputs)
		check(step.ok,"fixed Mission step")
		if not step.ok:
			return false
		confirmed.append_array(step.value.system_reports[0].value.hits)
	check(confirmed.size()==250,"250 physical hits confirmed before audio")
	check(output.transition_music("battle").ok,"battle score")
	for row in confirmed:
		var key: String = row.attack_id+"/%s"%row.target.index
		check(output.play_event(envelope(key,"hit",{"position_mm":poses[row.target.index].position_mm})).ok,"confirmed hits routed")
	var token := RefCounted.new()
	var formation := Formation.new(MID,func(t): return R.ok("player") if t==token else R.fail("Unauthorized"),func(_id,_pos): return true)
	check(formation.add_formation(1,"allies","player",roster).ok,"deploy commanded formation")
	var order := {"mission_id":MID,"issuer_id":"player","order_id":"order-1","client_sequence":1,"issued_tick":1,
		"formation_ids":[1],"order_type":"hold","parameters":{},"target_formation_id":null,"target_position":null}
	check(formation.issue_order(order,token,0).ok and formation.advance(1).ok and formation.view(1).value.active==order,"accepted formation command")
	var message := envelope(order.order_id,"command",{"order_type":order.order_type})
	var subs := []
	var notices := []
	output.subtitle_requested.connect(func(key,id): subs.append([key,id]))
	output.important_notice.connect(func(key,id): notices.append([key,id]))
	var receipt := output.play_event(message)
	var after := output.diagnostics()
	check(receipt.value.status=="played" and after.peak<=12 and after.played+after.dropped==251 and after.dropped>0 and after.caption=="坚守阵地！","priority speech, Chinese label and bounded playback")
	check(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(state.buses.Effects)) < -9,"actual effects ducking while command speaks")
	check(output.play_event(message).value.status=="duplicate_or_stale" and subs.size()==1,"no duplicate sound or subtitle")
	var predicted := envelope("future","warning",{"predicted":true})
	check(not output.play_event(predicted).ok,"prediction never speaks")
	check(not output.play_event(envelope("bad","hit",{"confirmed":1})).ok,"confirmed flag must be boolean")
	var old := message.duplicate(true)
	old.scope_id = "old-scope"
	check(not output.play_event(old).ok,"old Mission event rejected")
	var rhs := output.play_event(envelope("step","mount_impact",{"position_mm":[1000,0,0]}))
	check(rhs.value.status=="played","mounted effect preempts lower priority")
	var player: AudioStreamPlayer3D = output.find_children("*","AudioStreamPlayer3D",false,false)[rhs.value.slot-2]
	check(player.global_position.is_equal_approx(Vector3(1,0,0)) and player.max_distance==60,"actual spatial player pose and attenuation")
	var muffled := output.play_event(envelope("covered","shield_broken",{"position_mm":[2000,0,0],"occluded":true}))
	check(muffled.value.status=="played" and output.find_children("*","AudioStreamPlayer3D",false,false)[muffled.value.slot-2].volume_db==-10.0,"listener occlusion reduces spatial gain")
	check(output.play_event(envelope("far","hit",{"position_mm":[999000,0,0]})).value.status=="distance","far noise culled")
	await create_timer(0.42).timeout
	var samples := capture.get_buffer(capture.get_frames_available())
	for sample in samples:
		pcm_peak = maxf(pcm_peak,maxf(absf(sample.x),absf(sample.y)))
	check(samples.size()>100 and pcm_peak>0.005,"actual command signal PCM mixed into Voice bus")
	print("T-AUD-01-AUTO ", "PASS" if failures==0 else "FAIL"," actors=500 confirmed_hits=",confirmed.size()," budget=12 peak=",after.peak," dropped=",after.dropped," voice_pcm_frames=",samples.size()," pcm_peak=",pcm_peak," human_intelligibility=NOT_RUN")
	var before: int = failures
	var saved := output.set_mixer({"master":0.0,"voice":0.0,"effects":0.0,"subtitles":true})
	check(saved.ok,"save silent accessibility settings "+str(saved)+" "+ProjectSettings.globalize_path(path))
	check(not output.set_mixer({"voice":NAN}).ok and output.diagnostics().settings.voice==0,"reject nonfinite volume atomically")
	var silent := output.play_event(envelope("mute-command","command",{"order_type":"retreat"},5))
	check(silent.value.status=="muted" and output.diagnostics().caption=="撤退！","visible information while muted")
	check(mission.request_end({"outcome":"victory"}).ok and mission.finalize().value.outcome=="victory","finish the Mission")
	var win := output.play_event(envelope("end","victory",{},6))
	check(win.value.status=="muted" and output.diagnostics().track=="victory" and subs[-1][0]=="audio.victory" and output.diagnostics().caption=="获得胜利","silent victory event and localized subtitle")
	check(output.set_mixer({"music":0.0,"ui":1.0,"master":1.0}).ok,"mute only music")
	var losing := output.play_event(envelope("music-check","defeat",{},6))
	check(losing.value.status=="muted" and output.diagnostics().track=="defeat","outcome respects dedicated music bus")
	check(output.set_mixer({"master":0.0}).ok,"restore silent accessibility scenario")
	check(output.transition_music("silent").ok,"fade to silence")
	await create_timer(0.45).timeout
	check(output.find_children("*","AudioStreamPlayer",false,false).all(func(n): return not n.playing),"all music decks finish fade")
	check(output.set_mixer({"subtitles":false}).ok and output.diagnostics().caption=="","subtitle toggle")
	var muted_warning := output.play_event(envelope("after-end","warning",{},7))
	check(muted_warning.value.status=="muted" and notices[-1][0]=="audio.warning" and output.diagnostics().caption=="","critical text notice remains accessible to HUD with subtitles off")
	print("T-AUD-02 ","PASS" if failures==before else "FAIL"," silent_victory_caption=",subs[-1][0])
	before = failures
	check(mission.dispose().ok and output.stop_scope(MID).ok,"release simulation and sound scope")
	check(output.diagnostics().allocated==0 and AudioServer.bus_count==bus_count and output.get_child_count()==0,"no audio nodes, captions or buses after exit")
	check(output.open_scope("second",8,path).ok and output.diagnostics().settings.master==0 and not output.diagnostics().settings.subtitles,"settings restored across Mission")
	check(not output.play_event(message).ok,"old sounds cannot cross scope")
	var second := envelope("fresh","hit",{})
	second.scope_id = "second"
	check(output.set_mixer({"master":1,"effects":1,"voice":1}).ok and output.play_event(second).value.status=="played","second scope uses restored and edited mixer")
	check(output.play_event(dict_for_scope("later",50,"second")).ok and output.play_event(dict_for_scope("past",2,"second")).value.status=="duplicate_or_stale","late evicted frame cannot replay")
	output.important_notice.connect(func(_key,_id): output.stop_scope("second"),CONNECT_ONE_SHOT)
	var navigation := dict_for_scope("close",51,"second")
	navigation.type = "warning"
	check(output.play_event(navigation).value.status=="scope_closed" and output.get_child_count()==0,"HUD can close the Mission as it receives a notice")
	check(output.open_scope("last",4,"").ok and output.transition_music("battle").ok,"small independent scope")
	output.free()
	listener.free()
	await create_timer(0.12).timeout
	check(AudioServer.bus_count==bus_count,"owner destruction releases currently playing voices")
	var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check(remove_error==OK,"remove test-owned settings")
	print("T-AUD-03 ","PASS" if failures==before else "FAIL"," remaining_audio_buses=",AudioServer.bus_count-bus_count)
	return true

func dict_for_scope(id: String, tick: int, scope_id: String) -> Dictionary:
	var event := envelope(id,"hit",{},tick)
	event.scope_id = scope_id
	return event
