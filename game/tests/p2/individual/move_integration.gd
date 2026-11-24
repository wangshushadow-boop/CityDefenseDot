extends "res://tests/p2/individual/run.gd"

func run() -> void:
	engine = EnginePort.new(root,true)
	var token: Dictionary = engine.open_scope(SCOPE)
	check(engine.load_scene({"id":"base:scene/individual","simulation_scene":"res://tests/p2/individual/arena.tscn"},token.value).ok,"field loaded")
	for i in 120:
		await physics_frame
		var synced: Dictionary = engine.sync_navigation(SCOPE)
		if synced.ok and synced.value.status=="applied":
			nav = synced.value.applied_revision
			if path(Vector3(-8,0,8),Vector3(-11,0,8),nav):
				break
	var foot_ok := run_exit(false)
	var mounted_ok := run_exit(true)
	engine.release_scope(SCOPE)
	quit(0 if foot_ok and mounted_ok and errors==0 else 1)


func run_exit(mounted: bool) -> bool:
	var api: Script = Movement
	var ai_context := RefCounted.new()
	var player_context := RefCounted.new()
	var authorize := func(scope_id: String,subject: Dictionary,credential: Variant,tick: int) -> bool:
		return scope_id==SCOPE and subject==A and tick>0 and (is_same(credential,ai_context) or is_same(credential,player_context))
	var original: RefCounted = api.new(engine,SCOPE)
	if not original.has_method("apply_move_intent"):
		printerr("NOT_RUN P2-BAI-I-001 MOV input integration requires the P2 MOV intent candidate")
		return false
	var player: RefCounted = api.new(engine,SCOPE,authorize)
	var controlled: RefCounted = api.new(engine,SCOPE,authorize)
	var start := Vector3(-8,0,8)
	var exit_point := Vector3(-11,0,8)
	var profile := "mounted" if mounted else "foot"
	player.spawn(A,start,profile,Vector3.LEFT)
	controlled.spawn(A,start,profile,Vector3.LEFT)
	var com := Combat.new(SCOPE)
	if mounted:
		com.enlist(A,{"role":"cavalry","team":0,"morale":70,"ranged":"bow"})
		com.enlist(H,{"role":"mount","team":0})
		com.mount(A,H)
		com.step_field(1,[],{},Callable(),[{"actor_handle":A,"delta":-65}])
	else:
		com.enlist(A,{"role":"infantry","team":0,"morale":15})
	var ai := AI.new(SCOPE,clear_ray)
	var roster: Dictionary = ai.publish(0,nav,[unit(A,start,0,"mounted_archer" if mounted else "infantry")]).value
	var brain := Brain.new(SCOPE,ai.get_instance_id())
	var signals := 0
	var coasted := 0
	var stopped := false
	var discarded := false
	for t in range(1,181) if mounted else range(1,101):
		var p: Vector3 = controlled.view(A).value.position
		ai.advance(t,nav,roster,PackedVector3Array([p]),[A] if t==1 else [])
		var brain_draft: RefCounted = brain.fork()
		var proposed := {}
		for job in ai.schedule().value.jobs:
			if job.layer!="individual": continue
			var local := context(p)
			local.exit_position = exit_point
			var r: Dictionary = brain_draft.decide(job,ai.sense(A).value,com.view(A).value,ORDERS,local)
			check(r.ok and r.value.mode=="Routing","L3 reads actual routed combatant")
			if not r.ok: break
			proposed[job.id] = r.value
			check(ai.collect(job,r.value.intents).ok,"real BAI authority accepts canonical movement")
		var batches: Array = ai.drain().value
		var stage: Variant = controlled.begin_step(t).value
		var player_stage: Variant = player.begin_step(t).value
		var touched := false
		for batch in batches:
			var receipt := R.ok()
			for cmd in batch.intents:
				if not cmd.has("desired_direction"): continue
				touched = true
				signals += 1
				stopped = stopped or cmd.speed_fraction==0
				check(S.validate_shape("MoveIntent",cmd).ok,"same player/AI wire command")
				if not discarded:
					check(not controlled.apply_move_intent(stage,cmd,player).ok,"foreign controller denied")
					check(controlled.apply_move_intent(stage,cmd,ai_context).ok and controlled.stage_step(t,1.0/60,stage).ok,"prepare real move")
					check(controlled.rollback_step(stage).ok and controlled.view(A).value.position==p,"failed downstream tick leaves MOV untouched")
					stage = controlled.begin_step(t).value
					discarded = true
				receipt = controlled.apply_move_intent(stage,cmd,ai_context)
				check(receipt.ok and player.apply_move_intent(player_stage,cmd,player_context).ok,"both input sources use the identical MOV entry point")
			check(brain_draft.accept(batch,proposed[batch.job.id],R.ok(),receipt).ok,"record executed movement")
		check(controlled.stage_step(t,1.0/60,stage).ok and player.stage_step(t,1.0/60,player_stage).ok,"step both authorities")
		check(controlled.commit_step(stage).ok and player.commit_step(player_stage).ok,"commit same ticks")
		brain = brain_draft
		var position: Vector3 = controlled.view(A).value.position
		check(position.is_equal_approx(player.view(A).value.position),"player and AI position match")
		if not touched and p.distance_squared_to(position)>0.000001: coasted += 1
	var final_p: Vector3 = controlled.view(A).value.position
	check(discarded and signals<35 and coasted>10 and stopped and final_p.distance_to(exit_point)<0.45,"low cadence reaches real exit and stops")
	print("L3_MOV_INTEGRATION profile=",profile," ", "PASS" if errors==0 else "FAIL", " checks=",checks," errors=",errors," commands=",signals," unsampled_movement_ticks=",coasted," final=",final_p)
	return errors==0
