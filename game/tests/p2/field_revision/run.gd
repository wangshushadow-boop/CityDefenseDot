extends "res://tests/p2/field_pipeline/run.gd"

var reject_snapshot := true

func later_system(_ctx: Dictionary, batch: Dictionary) -> Dictionary:
	if reject_snapshot and batch.source_tick == 3:
		return R.fail("Unavailable","test.snapshot")
	return R.ok()

func profile_transition() -> void:
	if not await open(battle(["cavalry"],[1],1)): return
	if not ok(mission.register_system("snapshot",{"id":"zz.retry","run":later_system}),"install rollback probe"): return
	if not ok(mission.step_fixed(1,[]),"deploy real cavalry"): return
	var group: Dictionary = hud().formations.filter(func(g): return g.id==3)[0]
	var command := checked_order("player",1,"layout",{"layout":"wedge"},group.control_revision)
	command.order.formation_ids = [3]
	command.revisions = {3:group.control_revision-1}
	var stale: Dictionary = mission.gateway("field.order",command,token)
	check(not stale.ok and stale.error.code=="Conflict" and stale.error.field=="control_revision","refuse obsolete player grant")
	command.revisions[3] = group.control_revision
	if not ok(mission.gateway("field.order",command,token),"install wedge"): return
	if not ok(mission.step_fixed(2,[]),"publish new order revision"): return
	var rider: Dictionary = hud().player_handle
	var horse: Dictionary = hud().player.mount_handle
	var before: Dictionary = mission._layout_specs[3].duplicate(true)
	if not check(before.order_revision>1,"formation has prior order history"):return
	if not ok(input(3,[{"actor_handle":rider,"target_ref":"self","action":"dismount"}]),"admit dismount"):return
	var interrupted: Dictionary = mission.step_fixed(3,[])
	check(not interrupted.ok and interrupted.error.field=="test.snapshot","profile change reached downstream rollback: "+str(interrupted.get("error")))
	check(mission._layout_specs[3]==before and mission.view().tick==2 and hud().player.mount_handle==horse,"abort preserves layout, clock and mount")
	reject_snapshot=false
	if not ok(mission.step_fixed(3,[]),"retry same dismount"):return
	var unmounted_revision: int = mission._layout_specs[3].order_revision
	check(unmounted_revision==before.order_revision+1 and hud().player.mount_handle==null,"single revision after retried dismount")
	var target := "field/%d/%d"%[horse.index,horse.generation]
	if not ok(input(4,[{"actor_handle":rider,"target_ref":target,"action":"mount"}]),"admit remount"): return
	if not ok(mission.step_fixed(4,[]),"publish remount"): return
	check(mission._layout_specs[3].order_revision==unmounted_revision+1 and hud().player.mount_handle==horse,"remount rebuilds current movement lanes")

func run() -> void:
	var compiler := Compiler.new()
	var compiled := compiler.compile(compiler.scan_packages([Compiler.BASE_PACKAGE,"res://content/base/field"]),{})
	if not ok(compiled,"load resources"):
		quit(1)
		return
	registry=compiled.value.registry
	adapter=EngineAdapter.new(root,true)
	brain_script=preload("res://mission/runtime/field_brains.gd")
	await profile_transition()
	if mission!=null:mission.dispose()
	print("FIELD_REVISION checks=",checks," failures=",failed)
	quit(1 if failed else 0)
