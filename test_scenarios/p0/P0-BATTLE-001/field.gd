extends Node3D

const Rig = preload("res://rig.gd")
const SEED_VALUE = 241124
const WARM = 120
const SAMPLES = 360
const DT = 1.0 / 60.0
const G = Vector3(0, -9.8, 0)

class Fighter:
	var role: int
	var side: int
	var origin: Vector3
	var pos: Vector3
	var target: int
	var hp := 5
	var action := 0
	var attack_start := -90
	var next_decision := 0
	var phase: float
	var moved := false
	var human: Skeleton3D
	var horse: Skeleton3D

class Arrow:
	var pos: Vector3
	var velocity: Vector3
	var target: int
	var life: int
	var visual: MeshInstance3D

var count: int
var half: int
var output: String
var rng := RandomNumberGenerator.new()
var units: Array[Fighter] = []
var arrows: Array[Arrow] = []
var free_arrows: Array[MeshInstance3D] = []
var arrow_mesh := BoxMesh.new()
var camera := Camera3D.new()
var tick := 0
var last_frame := 0
var start := 0
var frames: Array = []
var ticks: Array = []
var peak_arrows := 0
var decisions := 0
var melee_hits := 0
var arrow_hits := 0
var downs := 0
var reserves := 0
var spawned := 0
var action_counts := [0, 0, 0, 0]
var sampled_initial: Array
var min_active: int
var min_visible_humans: int
var min_visible_horses: int
var peak_corpses := 0
var min_skinned := 0
var max_skinned := 0
var population: Array = []
var role_counts := [0, 0, 0]
var corpses: Array[Skeleton3D] = []
var expire_ticks: Array[int] = []
var free_corpses: Array[Skeleton3D] = []
var teams: Array[StandardMaterial3D] = []
var human_rig: Rig
var horse_rig: Rig

func material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	return m

func _ready():
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or int(args[0]) not in [500, 1000]:
		get_tree().quit(2)
		return
	count = int(args[0])
	output = args[1]
	var pid_file := FileAccess.open(output + ".pid", FileAccess.WRITE)
	pid_file.store_string(str(OS.get_process_id()))
	pid_file.close()
	half = count / 2
	min_active = count
	min_visible_humans = count
	min_visible_horses = count / 5
	min_skinned = count * 10
	rng.seed = SEED_VALUE
	human_rig = Rig.new(false)
	horse_rig = Rig.new(true)
	teams.assign([material(Color("9e302b")), material(Color("32699b"))])
	var coat := material(Color("704124"))
	for i in count:
		var u := Fighter.new()
		u.side = i / half
		var slot := i % half
		u.role = 0 if slot % 10 < 5 else (1 if slot % 10 < 8 else 2)
		var width := 25 if count == 500 else 40
		var sign_z := 1 if u.side == 0 else -1
		role_counts[u.role] += 1
		u.origin = Vector3((slot % width - width * .5) * 1.3 + rng.randf_range(-.15,.15),
			0, sign_z * (2.2 + (slot / width) * 1.15))
		u.pos = u.origin
		u.phase = rng.randf_range(0, TAU)
		u.next_decision = i % 8
		u.target = ((1-u.side) * half) + slot
		u.human = human_rig.spawn(self, teams[u.side])
		if u.role == 2:
			u.horse = horse_rig.spawn(self, coat)
		units.append(u)
	var terrain := MeshInstance3D.new()
	var ground := PlaneMesh.new()
	ground.size = Vector2(130, 100)
	terrain.mesh = ground
	terrain.material_override = material(Color("69834c"))
	add_child(terrain)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -36, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 105
	add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("aac3da")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("d4deef")
	env.ambient_light_energy = .62
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	arrow_mesh.size = Vector3(.055, .055, .75)
	add_child(camera)
	camera.fov = 60
	move_camera()
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)

func move_camera():
	camera.position = Vector3(6.0 * sin(tick * DT * .4), 38, 45)
	camera.look_at(Vector3(0, .5, 0))

func select_target(i: int):
	var u := units[i]
	var base := (1-u.side) * half
	var slot := i % half
	var best_squared := INF
	# Local formation-neighbour search includes the opposed file and adjacent opponents.
	for offset in [0, -1, 1, -2, 2, -5, 5]:
		var j := base + posmod(slot + int(offset), half)
		var other := units[j]
		if other.hp <= 0:
			continue
		var distance := u.pos.distance_squared_to(other.pos)
		if distance < best_squared:
			best_squared = distance
			u.target = j
	decisions += 1

func damage(j: int):
	var u := units[j]
	if u.hp <= 0:
		return
	u.hp -= 1
	if u.hp == 0:
		downs += 1

func renew_front_line():
	# Keep defeated proxies for 18 ticks; the reserve owns a separate, live skeleton.
	for index in range(corpses.size()-1, -1, -1):
		if tick >= expire_ticks[index]:
			corpses[index].visible = false
			free_corpses.append(corpses[index])
			corpses.remove_at(index)
			expire_ticks.remove_at(index)
	for u in units:
		if u.hp > 0:
			continue
		var body := u.human
		body.rotation.z = PI*.5
		body.position = u.pos + Vector3.UP*.22
		corpses.append(body)
		expire_ticks.append(tick + 18)
		if free_corpses.is_empty():
			u.human = human_rig.spawn(self, teams[u.side])
		else:
			u.human = free_corpses.pop_back()
			u.human.reset_bone_poses()
			u.human.get_child(0).material_override = teams[u.side]
			u.human.visible = true
		u.hp = 5
		u.pos = u.origin
		u.attack_start = -90
		u.next_decision = tick + 1
		u.human.rotation = Vector3(0, 0 if u.side == 0 else PI, 0)
		u.human.position = u.pos + Vector3.UP * (1.02 if u.horse else 0.0)
		if u.horse:
			u.horse.position = u.pos
		reserves += 1

func measure_population():
	var alive := 0
	var visible_humans := 0
	var visible_horses := 0
	for u in units:
		if u.hp > 0:
			alive += 1
		if u.human.is_visible_in_tree() and camera.is_position_in_frustum(u.human.position + Vector3.UP):
			visible_humans += 1
		if u.horse and u.horse.is_visible_in_tree() and camera.is_position_in_frustum(u.horse.position + Vector3.UP):
			visible_horses += 1
	min_active = mini(min_active, alive)
	min_visible_humans = mini(min_visible_humans, visible_humans)
	min_visible_horses = mini(min_visible_horses, visible_horses)
	var visible_skeletons := visible_humans + visible_horses
	for body in corpses:
		if body.is_visible_in_tree() and camera.is_position_in_frustum(body.position):
			visible_skeletons += 1
	min_skinned = mini(min_skinned, visible_skeletons)
	max_skinned = maxi(max_skinned, visible_skeletons)
	peak_corpses = maxi(peak_corpses, corpses.size())
	population = [alive, visible_humans, visible_horses, corpses.size(), visible_skeletons]

func shoot(u: Fighter):
	var a := Arrow.new()
	a.pos = u.pos + Vector3.UP * 1.32
	a.target = u.target
	var dst := units[a.target].pos + Vector3.UP * 1.03
	var duration := maxf(.15, a.pos.distance_to(dst) / 20.0)
	a.velocity = (dst - a.pos - .5 * G * duration * duration) / duration
	a.life = 100
	if free_arrows.is_empty():
		a.visual = MeshInstance3D.new()
		a.visual.mesh = arrow_mesh
		add_child(a.visual)
	else:
		a.visual = free_arrows.pop_back()
	a.visual.visible = true
	a.visual.position = a.pos
	arrows.append(a)
	spawned += 1

func step_arrows():
	for n in range(arrows.size()-1, -1, -1):
		var a := arrows[n]
		var next := a.pos + a.velocity * DT + .5 * G * DT * DT
		var hit := false
		var base := (a.target / half) * half
		for offset in [0, -1, 1]:
			var j := base + posmod(a.target % half + int(offset), half)
			var u := units[j]
			if u.hp <= 0:
				continue
			var center := u.pos + Vector3.UP * (1.50 if u.horse else 1.03)
			var nearest := Geometry3D.get_closest_point_to_segment(center, a.pos, next)
			if nearest.distance_squared_to(center) <= .48 * .48:
				damage(j)
				arrow_hits += 1
				hit = true
				break
		a.life -= 1
		if hit or next.y < .05 or a.life <= 0:
			a.visual.visible = false
			free_arrows.append(a.visual)
			arrows.remove_at(n)
		else:
			a.visual.position = next
			a.visual.look_at(next + a.velocity.normalized())
			a.pos = next
			a.velocity += G * DT

func update_unit(i: int):
	var u := units[i]
	if u.hp > 0:
		if tick >= u.next_decision:
			select_target(i)
			u.next_decision = tick + 8
		var enemy := units[u.target]
		var delta_pos := enemy.pos - u.pos
		var distance := delta_pos.length()
		var reach := 11.0 if u.role == 1 else 1.36
		if distance > reach:
			var speed := 5.9 if u.horse else 3.0
			u.pos += delta_pos / distance * minf(speed * DT, distance-reach)
			u.moved = true
		if distance < reach + .3 and enemy.hp > 0 and tick - u.attack_start >= 42 + i%11:
			u.attack_start = tick
			u.action = (u.action + i%3 + 1) % 4
			action_counts[u.action] += 1
		if tick - u.attack_start == 10 and enemy.hp > 0:
			if u.role == 1:
				shoot(u)
			elif distance > .01:
				var forward := delta_pos / distance
				var side := forward.cross(Vector3.UP)
				var shoulder := u.pos + Vector3.UP * 1.22
				var tip := shoulder + forward * 1.52
				var start_tip := tip - side * .76
				var end_tip := tip + side * .76
				match u.action:
					1:
						start_tip = tip + side * .76
						end_tip = tip - side * .76
					2:
						start_tip = tip + Vector3.UP * .78
						end_tip = tip - Vector3.UP * .48
					3:
						start_tip = shoulder + forward * .48
						end_tip = shoulder + forward * 1.82
				var center := enemy.pos + Vector3.UP * 1.2
				if Geometry3D.get_closest_point_to_segment(center, start_tip, end_tip).distance_squared_to(center) <= .68*.68:
					damage(u.target)
					melee_hits += 1
	var stride := sin(u.phase + tick * (.16 if u.horse else .12))
	var yaw := 0.0 if u.side == 0 else PI
	var human := u.human
	human.position = u.pos + Vector3.UP * (1.02 if u.horse else 0.0)
	human.rotation = Vector3(0, yaw, 0 if u.hp > 0 else PI*.5)
	human.set_bone_pose_rotation(5, Quaternion(Vector3.RIGHT, stride*.38))
	human.set_bone_pose_rotation(6, Quaternion(Vector3.RIGHT, -stride*.38))
	var stage := clampf((tick-u.attack_start)/22.0, 0, 1)
	var swing := sin(stage*PI)
	var shoulder_rest := human.get_bone_rest(4).origin
	var arm := Quaternion(Vector3.RIGHT, .22 * stride)
	match u.action:
		0, 1:
			var twist := (1 if u.action == 0 else -1) * swing
			arm = Quaternion(Vector3.UP, twist*1.25) * Quaternion(Vector3.RIGHT, 1.1*swing)
		2:
			arm = Quaternion(Vector3.RIGHT, swing*2.0)
		3:
			# A thrust extends the weapon forward; retract before the next attack.
			arm = Quaternion(Vector3.RIGHT, swing*1.45)
			shoulder_rest.z -= .30 * swing
	human.set_bone_pose_position(4, shoulder_rest)
	human.set_bone_pose_rotation(4, arm)
	human.set_bone_pose_rotation(3, Quaternion(Vector3.RIGHT, -stride*.25))
	if u.horse:
		u.horse.position = u.pos
		u.horse.rotation.y = yaw
		for leg in range(3, 7):
			u.horse.set_bone_pose_rotation(leg, Quaternion(Vector3.RIGHT, stride*(.39 if leg in [3,6] else -.39)))

func counters() -> Array:
	return [decisions, melee_hits, arrow_hits, downs, reserves, spawned] + action_counts

func _physics_process(_delta: float):
	if count == 0 or tick >= WARM+SAMPLES:
		return
	var begin := Time.get_ticks_usec()
	tick += 1
	for i in count:
		update_unit(i)
	step_arrows()
	renew_front_line()
	move_camera()
	if tick > WARM:
		measure_population()
	var end := Time.get_ticks_usec()
	if tick == WARM:
		start = end
		sampled_initial = counters()
	elif tick > WARM:
		ticks.append([tick, end-begin, end-start] + population)
		peak_arrows = maxi(peak_arrows, arrows.size())

func _process(_delta: float):
	if tick < WARM:
		return
	var now := Time.get_ticks_usec()
	var vp := get_viewport().get_viewport_rid()
	if last_frame != 0:
		frames.append([now-last_frame, RenderingServer.viewport_get_measured_render_time_cpu(vp),
			RenderingServer.viewport_get_measured_render_time_gpu(vp),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)])
	last_frame = now
	if tick < WARM+SAMPLES:
		return
	var activity := counters()
	for i in activity.size():
		activity[i] -= sampled_initial[i]
	var moved := 0
	for u in units:
		if u.moved:
			moved += 1
	var data := {"frames":frames, "ticks":ticks, "activity":activity, "min_active":min_active,
		"peak_arrows":peak_arrows, "moved_units":moved, "count":count, "seed":SEED_VALUE,
		"roles":role_counts, "min_visible_humans":min_visible_humans, "min_visible_horses":min_visible_horses,
		"peak_corpses":peak_corpses, "min_visible_skeletons":min_skinned, "max_visible_skeletons":max_skinned,
		"human_bones":7, "horse_bones":7,
		"human_triangles":human_rig.mesh.surface_get_array_index_len(0)/3,
		"horse_triangles":horse_rig.mesh.surface_get_array_index_len(0)/3,
		"pixels":[get_viewport().size.x,get_viewport().size.y],
		"display":DisplayServer.get_name(), "adapter":RenderingServer.get_video_adapter_name(),
		"renderer":RenderingServer.get_current_rendering_method(), "driver":RenderingServer.get_current_rendering_driver_name(),
		"vsync":DisplayServer.window_get_vsync_mode(), "engine":Engine.get_version_info().string}
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		get_tree().quit(4)
		return
	file.store_string(JSON.stringify(data))
	file.close()
	get_tree().quit(0)
