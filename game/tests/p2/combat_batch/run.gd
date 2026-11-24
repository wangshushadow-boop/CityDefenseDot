extends SceneTree

const Combat = preload("res://mission/combat/ports/field_combat.gd")
const S = preload("res://contracts/schema.gd")
const R = preload("res://contracts/result.gd")
const A := {"index":0, "generation":1}
const B := {"index":1, "generation":1}
const HORSE := {"index":2, "generation":1}
const SCOPE := "combat-batch"
var errors := 0
var assertions := 0


func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:
		errors += 1
		printerr("FAIL ", label)


func block() -> Dictionary:
	return {"actor_handle":A.duplicate(), "direction":"up", "held":true}


func attack(phase: String, slot: int) -> Dictionary:
	return {"actor_handle":A.duplicate(), "direction":"thrust", "input_phase":phase, "weapon_slot":slot, "target_hint":null}


func canonical_parity() -> void:
	var cases := []
	for change in [{"extra":0}, {"held":1}, {"direction":3}, {"direction":&"up"},
			{"actor_handle":{"generation":1,"index":0.0}}, {"actor_handle":{"generation":1.0,"index":0}},
			{"actor_handle":{"generation":0,"index":0}}, {"actor_handle":{"generation":1,"index":4294967296}},
			{"actor_handle":{"generation":1,"index":0,"scope_id":"elsewhere"}},
			{"actor_handle":{&"index":0,"generation":1}}, {"direction":"e\u0301"}]:
		var item := block()
		item.merge(change,true)
		cases.append(["BlockIntent", item])
	var named_key := block()
	named_key.erase("direction")
	named_key[&"direction"] = "up"
	cases.append(["BlockIntent",named_key])
	var missing := attack("start",0)
	missing.erase("target_hint")
	cases.append(["AttackIntent",missing])
	for change in [{"weapon_slot":-1},{"weapon_slot":0.0},{"input_phase":&"start"},{"target_hint":{}},
			{"target_hint":{"index":0,"generation":0}},{"target_hint":{"index":0,"generation":1,"fake":false}}]:
		var item := attack("start",0)
		item.merge(change,true)
		cases.append(["AttackIntent",item])
	for pair in cases:
		var sim := Combat.new(SCOPE)
		sim.add_actor(A)
		var shape: Dictionary = S.validate_shape(pair[0],pair[1])
		var result: Dictionary = sim.step_field(1,[block(),pair[1]],{},Callable())
		check(not shape.ok and result == shape,"exact v1 structural errors: "+str(pair[1]))
		check(sim.view(A).value.phase == "Ready" and sim.step_field(1,[block()],{},Callable()).ok,"malformed tail rolls back")
	for change in [{"input_phase":"future"},{"direction":"north"},{"weapon_slot":2}]:
		var sim := Combat.new(SCOPE)
		sim.add_actor(A)
		var item := attack("start",0)
		item.merge(change,true)
		var step: Dictionary = sim.step_field(1,[item],{},Callable())
		check(S.validate_shape("AttackIntent",item).ok and step.ok and step.value.receipts[0] == R.fail("InvalidArgument",change.keys()[0]),"canonical domain errors preserved")
	var gen := Combat.new(SCOPE)
	gen.add_actor(A)
	var stale := block()
	stale.actor_handle = {"index":0,"generation":2}
	var start := attack("start",0)
	start.target_hint = {"index":4294967295,"generation":4294967295}
	var receipt: Dictionary = gen.step_field(1,[stale,start,start],{},Callable())
	check(receipt.ok and receipt.value.receipts == [R.fail("NotFound","actor_handle"),R.ok(),R.fail("InvalidState","start")],"ordered duplicate, stale and maximum optional handle")
	check(gen.step_field(1,[],{},Callable()) == R.fail("StaleVersion","tick"),"duplicate tick")


func projection() -> void:
	var sim := Combat.new(SCOPE)
	sim.enlist(A,{"team":0,"role":"archer"})
	sim.enlist(B,{"team":0,"role":"cavalry"})
	sim.enlist(HORSE,{"team":0,"role":"mount"})
	sim.mount(B,HORSE)
	var visible: Dictionary = sim.field_view(SCOPE,[HORSE,B,A],0).value
	check(visible.actors[1].mount_handle==HORSE and visible.actors[1].mount_handle.is_read_only() and visible.actors[2].role=="archer","ordered actual mount and role")
	check(visible.is_read_only() and visible.actors.is_read_only() and visible.actors[1].is_read_only() and visible.actors[0].handle.is_read_only(),"immutable nested actor view")
	check(not visible.actors[1].has("hit_set") and not visible.actors[1].has("armor"),"authority details private")
	check(not sim.field_view("other",[A]).ok and not Combat.new().field_view("",[]).ok,"foreign and unbound scope")
	check(not sim.field_view(SCOPE,[A,A]).ok and not sim.field_view(SCOPE,[],4097).ok and not sim.field_view(SCOPE,[],1.0).ok and sim.field_view(SCOPE,[],0).ok,"bounds and duplicates")
	var poses := {0:{"position_mm":[0,1000,0],"facing_ppm":[1000000,0,0]}}
	var clear := func(_queries,_tick): return R.ok([])
	for t in range(1,4):
		sim.step_field(t,[attack("start",1)] if t==1 else [],poses,clear)
	var fork: RefCounted = sim.fork()
	var shot := [attack("release",1)]
	var rejected: Dictionary = fork.step_field(4,shot,poses,func(_q,_tick): return R.fail("Unavailable","sweep"))
	check(not rejected.ok and fork.field_view(SCOPE,[A]).value == sim.field_view(SCOPE,[A]).value,"uncommitted release and clock discarded")
	fork.step_field(4,shot,poses,clear)
	var at_four: Dictionary = fork.field_view(SCOPE,[A]).value
	check(at_four.tick==4 and at_four.projectile_count==1 and at_four.actors[0].ammo==7 and at_four.actors[0].phase=="Active","committed branch with flight")
	var p: Dictionary = at_four.projectiles[0]
	check(at_four.projectiles.is_read_only() and p.is_read_only() and p.keys().size()==3 and p.id=="4:0:1","bounded projectile has no private striker state")
	check(p.position.is_equal_approx(Vector3(1.7,1,0)) and p.direction.is_equal_approx(Vector3(1700,-3,0).normalized()),"flight converted mm to metres and normalized direction")
	check(fork.field_view(SCOPE,[],0).value.projectiles.is_empty() and sim.field_view(SCOPE,[]).value.projectile_count==0,"cap and unpublished branch isolated")
	fork.remove_actor(A)
	var replacement := {"index":0,"generation":2}
	fork.add_actor(replacement)
	check(not fork.field_view(SCOPE,[A]).ok and fork.field_view(SCOPE,[replacement]).value.actors[0].phase=="Ready","stale handle cannot read replacement")
	fork.step_field(5,[],poses,clear)
	var next: Dictionary = fork.field_view(SCOPE,[]).value
	check(next.projectiles[0].id==p.id and next.projectiles[0].position.x>p.position.x and at_four.projectiles[0].position==p.position,"retired shooter, stable flight and detached prior view")
	fork.step_field(6,[],poses,func(_q,_t): return R.ok([{"query_index":0,"fraction_ppm":100,"target":null}]))
	check(fork.field_view(SCOPE,[]).value.projectiles.is_empty() and fork.field_view(SCOPE,[replacement]).value.actors[0].phase=="Ready","impact removes flight and removed actor clocks cannot advance a successor")
	fork.remove_actor(HORSE)
	check(fork.view(B).value.phase=="Stagger","dismount outside step starts a clock")
	fork.step_field(7,[],{},clear)
	fork.step_field(8,[],{},clear)
	check(fork.view(B).value.phase=="Ready" and visible.actors[1].mount_handle==HORSE,"fall recovery and detached old link")


func view_load(population: int) -> void:
	var sim := Combat.new(SCOPE)
	var handles := []
	for i in population:
		var h := {"index":i,"generation":1}
		sim.enlist(h,{"team":i%2,"role":"archer" if i%3==0 else "infantry"})
		handles.append(h)
	var scalar := []
	var batch := []
	for t in range(1,61):
		var intents := []
		for i in range(t%12,population,12):
			intents.append({"actor_handle":handles[i],"direction":"up","held":true})
		sim = sim.fork()
		sim.step_field(t,intents,{},Callable())
		var start := Time.get_ticks_usec()
		for handle in handles:
			sim.view(handle)
		var half := Time.get_ticks_usec()
		var visible: Dictionary = sim.field_view(SCOPE,handles)
		var end := Time.get_ticks_usec()
		check(visible.ok and visible.value.actors.size()==population and visible.value.tick==t,"crowd projection")
		scalar.append(half-start)
		batch.append(end-half)
	scalar.sort()
	batch.sort()
	print("COM_VIEW people=",population," ticks=60 individual_p95_us=",scalar[56]," batch_p95_us=",batch[56])


func _initialize() -> void:
	canonical_parity()
	projection()
	if "--view-load" in OS.get_cmdline_user_args():
		view_load(500)
		view_load(1000)
	print("P2-BAI-003 ", "PASS" if errors==0 else "FAIL", " assertions=",assertions," errors=",errors)
	quit(0 if errors==0 else 1)
