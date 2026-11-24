extends SceneTree
## VIS-only deterministic projection replay. The full-field gate additionally
## runs authoritative movement, combat, AI, application, HUD and audio.
const Vis = preload("res://presentation/visuals/ports/field_visuals.gd")
const WARM := 120
const MEASURE := 360
const SCOPE := "visual-mixed-field"
var vis: Vis
var camera := Camera3D.new()
var amount: int
var out_file: String
var image_file: String
var actors := []
var origins := PackedVector3Array()
var seeds := PackedFloat32Array()
var tick := 0
var last_frame := 0
var started := 0
var frames := []
var ticks := []
var min_near := 1000
var min_far := 2000
var ready_for_test := false
var finished := false

func _initialize() -> void:
	call_deferred("setup")

func setup() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size()!=3 or int(args[0]) not in [500,1000]:
		quit(2)
		return
	amount = int(args[0])
	out_file = args[1]
	image_file = args[2]
	vis = Vis.new()
	root.add_child(vis)
	var ok := vis.open_field(SCOPE)
	if not ok.ok:
		printerr(ok)
		quit(3)
		return
	root.add_child(camera)
	camera.fov = 58
	camera.current = true
	root.msaa_3d = Viewport.MSAA_2X
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 241124
	for i in amount:
		var side := i / (amount/2)
		var slot := i % (amount/2)
		var role := "infantry" if slot%10 < 5 else ("archer" if slot%10 < 8 else "cavalry")
		var direction := -1 if side==0 else 1
		var j := slot / 25
		var start := Vector3(direction*(2.5+j*.82),0,(slot%25-12)*.96)
		start.x += rng.randf_range(-.18,.18)
		start.z += rng.randf_range(-.15,.15)
		origins.append(start)
		seeds.append(rng.randf_range(0,TAU))
		var hand := {"index":i,"generation":1}
		var actor := {"handle":hand,"role":role,"team":side,"since":0,"phase":"Ready","direction":"",
			"mount_handle":null,"position":start,"heading":Vector3(-direction,0,0),
			"velocity":Vector3.ZERO,"weapon_slot":1 if role=="archer" else 0}
		actors.append(actor)
	var horse_slot := amount
	for i in amount:
		var rider: Dictionary = actors[i]
		if rider.role != "cavalry": continue
		var horse := rider.duplicate()
		horse.handle = {"index":horse_slot,"generation":1}
		horse.role = "mount"
		rider.mount_handle = horse.handle
		actors.append(horse)
		origins.append(origins[i])
		seeds.append(seeds[i])
		horse_slot += 1
	ready_for_test = true

func _physics_process(_dt: float) -> bool:
	if not ready_for_test or tick >= WARM+MEASURE: return false
	var begin := Time.get_ticks_usec()
	tick += 1
	var missiles := []
	var events := []
	for i in actors.size():
		var a: Dictionary = actors[i]
		var angle := tick/60.0 + seeds[i]
		var dir: Vector3 = a.heading
		var advance := sin(angle)*.83
		a.position = origins[i] + dir*advance + Vector3.BACK*.25*sin(angle*.8)
		a.velocity = dir*cos(angle)*1.65 + Vector3.BACK*.20*cos(angle*.8)
		var period := (tick+(i%47))%48
		if a.role != "mount":
			var phase := "Ready"
			if period < 5: phase = "Windup"
			elif period < 12: phase = "Hold"
			elif period < 14: phase = "Active"
			elif period < 18: phase = "Recovery"
			elif period < 24: phase = "Guard"
			if a.phase != phase: a.since = tick
			a.phase = phase
			a.direction = ["up","left","right","thrust"][(i+tick/48)%4]
		if a.role=="archer" and period < 24:
			var travel := period/24.0
			missiles.append({"id":"%d-%d"%[i,(tick+(i%47))/48],"direction":dir,
				"position":Vector3(a.position)+Vector3.UP*(1.4+sin(travel*PI)*1.8)+dir*travel*12})
		if i < amount and i%17==0 and period==13:
			events.append({"event_id":"h%d-%d"%[tick,i],"actor_handle":a.handle,"confirmed":true,"type":"hit"})
		if a.role in ["infantry","archer"] and i%79==0 and period==17:
			events.append({"event_id":"c%d-%d"%[tick,i],"actor_handle":a.handle,"confirmed":true,
				"type":"downed","role":a.role,"team":a.team,"position":a.position})
			a.handle = {"index":i,"generation":a.handle.generation+1}
	var accepted := vis.apply_snapshot({"scope_id":SCOPE,"tick":tick,"actors":actors,"projectiles":missiles})
	if not accepted.ok:
		printerr(accepted)
		quit(4)
		return false
	vis.consume_view_events(SCOPE,tick,events)
	camera.position = Vector3(4.5*sin(tick/150.0),24,44)
	camera.look_at(Vector3(0,1,0))
	var now := Time.get_ticks_usec()
	if tick==WARM: started = now
	elif tick>WARM: ticks.append([tick,now-begin,now-started])
	return false

func _process(_dt: float) -> bool:
	if not ready_for_test or tick == 0 or finished: return false
	var now := Time.get_ticks_usec()
	vis.render_interpolated(Engine.get_physics_interpolation_fraction(),camera.global_position,53)
	if tick>=WARM:
		var r := vis.report()
		min_near = mini(min_near,r.near_skeletons)
		min_far = mini(min_far,r.far_animated_instances)
		if r.visible_actors!=actors.size() or r.mounts!=amount/5:
			printerr("lost visual population ",r)
			quit(5)
			return false
		if last_frame:
			var vp := root.get_viewport_rid()
			frames.append([now-last_frame,RenderingServer.viewport_get_measured_render_time_cpu(vp),
				RenderingServer.viewport_get_measured_render_time_gpu(vp),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)])
		last_frame = now
	if tick==WARM+MEASURE:
		finished = true
		call_deferred("finish")
	return false

func finish() -> void:
	var in_frustum := 0
	for a: Dictionary in actors:
		if camera.is_position_in_frustum(a.position+Vector3.UP): in_frustum+=1
	var data := {"people":amount,"horses":amount/5,"in_frustum":in_frustum,"near_min":min_near,
		"far_min":min_far,"seed":241124,"pixels":[root.size.x,root.size.y],
		"adapter":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),
		"renderer":RenderingServer.get_current_rendering_method(),"vsync":DisplayServer.window_get_vsync_mode(),
		"metrics":vis.report(),"frames":frames,"ticks":ticks}
	var file := FileAccess.open(out_file,FileAccess.WRITE)
	if not file:
		quit(6)
		return
	file.store_string(JSON.stringify(data))
	file.close()
	if not image_file.is_empty():
		await RenderingServer.frame_post_draw
		if root.get_texture().get_image().save_png(image_file)!=OK:
			quit(7)
			return
		# An additional close inspection of the hand rig, mounts, and faction cloth.
		camera.position = Vector3(.1,3.6,16.0)
		camera.look_at(Vector3(-3.3,1.18,5.4))
		vis.render_interpolated(1.0,camera.position,22)
		await RenderingServer.frame_post_draw
		if root.get_texture().get_image().save_png(image_file.get_basename()+"-close.png")!=OK:
			quit(8)
			return
	print("VIS_GRAPHICS_OK ",amount," ",vis.report())
	vis.release_scope(SCOPE)
	vis.free()
	quit(0)
