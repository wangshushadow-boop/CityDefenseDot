class_name BattlefieldView extends Node3D
## 战场视图把模拟平面映射为三维 X/Z，模型和门扇只读战场状态。
const SoldierModel := preload("res://presentation/soldier_view.gd")
const CITY_GATE := preload("res://presentation/assets/polyfork/city_gate.glb")
const CAMP_GATE := preload("res://presentation/assets/polyfork/camp_gate.glb")
const WALL := preload("res://presentation/assets/polyfork/city_wall_run.glb")
const GRANARY := preload("res://presentation/assets/polyfork/raised_granary.glb")
const BANNER := preload("res://presentation/assets/polyfork/faction_banner_pole.glb")
const Terrain := preload("res://battle/terrain.gd")
const Valley := preload("res://presentation/valley_view.gd")
const CommanderCamera := preload("res://presentation/commander_camera.gd")
var mission: BattleMission
var camera := CommanderCamera.new()
var models: Dictionary = {}
var gates: Array[Array] = []
var sides: Array[Array] = []
var rams: Array[MeshInstance3D] = []
var flags: Array[MeshInstance3D] = []
var marker: MeshInstance3D
const COLORS := [Color("#46c6dd"), Color("#ef886a")]

func place(scene: PackedScene, at: Vector2, size: Vector3, yaw: float = 0.0) -> Node3D:
	var model: Node3D = scene.instantiate()
	model.rotation.y = yaw
	model.scale = size
	model.position = Vector3(at.x, Terrain.height(at), at.y)
	add_child(model)
	return model

func build_fort(fort: BattleFort, uniform: Material) -> void:
	var facing := 1.0 if fort.side == 0 else -1.0
	var yaw := facing * PI / 2
	# 本地 X 轴横跨门洞；把两扇门的铰链所在平面对齐模拟墙线。
	var main := place(CITY_GATE, fort.gate - Vector2(facing * 2.92 * 0.22, 0),
		Vector3(BattleSpace.HALF_GAP / 1.62, 0.48, 0.22), yaw)
	var side_at := fort.gate + Vector2(0, BattleSpace.SIDE_Z)
	var side := place(CAMP_GATE, side_at - Vector2(facing * 0.9 * 0.25, 0),
		Vector3(BattleSpace.HALF_GAP / 1.93, 0.55, 0.25), yaw)
	gates.append([main.get_node("han-city-gatehouse/door-l"), main.get_node("han-city-gatehouse/door-r")])
	sides.append([side.get_node("camp-gate/leaf-l"), side.get_node("camp-gate/leaf-r")])
	# 补齐两个门楼之间及城墙两端的空间，两个洞口保持四米宽。
	for span in [Vector2(-BattleSpace.LIMIT.y, -4), Vector2(4, side_at.y - 4.14), Vector2(side_at.y + 4.14, BattleSpace.LIMIT.y)]:
		var count := ceili((span.y - span.x) / 4.0)
		var width: float = (span.y - span.x) / count
		for i in count:
			place(WALL, Vector2(fort.gate.x, span.x + (i + 0.5) * width), Vector3(width / 4, 0.48, 0.34), yaw)
	var banner := place(BANNER, fort.yard() + Vector2(0, -3.2), Vector3.ONE * 0.66)
	var cloth := banner.get_node("faction-banner-pole/banner/banner-mesh") as MeshInstance3D
	cloth.material_override = uniform

func set_leaves(leaves: Array, opened: bool, broken: bool) -> void:
	for i in leaves.size():
		var leaf: Node3D = leaves[i]
		leaf.visible = not broken
		leaf.rotation.y = (PI / 2 if i == 0 else -PI / 2) if opened else 0.0

func block(at: Vector2, size: Vector3, color: Color, height := 0.0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	node.material_override = mat
	node.position = Vector3(at.x, height + size.y / 2.0, at.y)
	add_child(node)
	return node

func caption(at: Vector2, value: String, h := 2.5) -> void:
	var label := Label3D.new()
	label.text = value
	label.position = Vector3(at.x, Terrain.height(at) + h, at.y)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.pixel_size = 0.0011
	label.font_size = 30
	add_child(label)

func build(current: BattleMission) -> void:
	mission = current
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-64, 28, 0)
	light.shadow_enabled = true
	light.shadow_opacity = 0.55
	add_child(light)
	var world_light := WorldEnvironment.new()
	world_light.environment = Environment.new()
	world_light.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world_light.environment.ambient_light_color = Color("#e4e2d6")
	world_light.environment.ambient_light_energy = 0.50
	world_light.environment.background_mode = Environment.BG_SKY
	world_light.environment.sky = Sky.new()
	var sky := ProceduralSkyMaterial.new()
	sky.sky_top_color = Color("#699bc2")
	sky.sky_horizon_color = Color("#e8dcbf")
	sky.ground_horizon_color = sky.sky_horizon_color
	world_light.environment.sky.sky_material = sky
	world_light.environment.fog_enabled = true
	world_light.environment.fog_density = 0.0028
	world_light.environment.fog_light_color = Color("#c3cfc7")
	add_child(world_light)
	add_child(camera)
	camera.current = true
	var valley := Valley.new()
	add_child(valley)
	valley.build(mission.field.terrain)
	var uniforms: Array[StandardMaterial3D] = []
	for fort in mission.field.forts:
		var uniform := StandardMaterial3D.new()
		uniform.albedo_color = COLORS[fort.side].darkened(0.32)
		uniforms.append(uniform)
		build_fort(fort, uniform)
		rams.append(block(fort.yard(), Vector3(2.0, 0.8, 1.0), Color.PERU))
	for point in mission.supply.points:
		var ring := TorusMesh.new()
		ring.inner_radius = 2.71
		ring.outer_radius = 2.8
		var indicator := MeshInstance3D.new()
		indicator.mesh = ring
		indicator.material_override = StandardMaterial3D.new()
		indicator.position = Vector3(point.at.x, Terrain.height(point.at) + 0.12, point.at.y)
		add_child(indicator)
		flags.append(indicator)
		caption(point.at, point.title)
	# 粮仓置于占领圈后侧，士兵和地面指令目标在俯视镜头下仍可见。
	place(GRANARY, BattleSpace.GRAIN + Vector2(0, -3.8), Vector3.ONE * 0.58)
	for team in mission.teams:
		for unit in team.units:
			var soldier := SoldierModel.new()
			add_child(soldier)
			soldier.build(unit, unit == team.leader, uniforms[team.side])
			models[unit] = soldier
	marker = block(Vector2.ZERO, Vector3(1.3, 0.12, 1.3), Color.GOLD, 0.15)
	refresh(Vector2.ZERO, 0.0)

func refresh(aim: Vector2, dt: float) -> void:
	for unit: BattleAgent in models:
		var model: SoldierModel = models[unit]
		model.sync(unit, dt)
	for fort in mission.field.forts:
		set_leaves(gates[fort.side], fort.front_open(), fort.gate_hp <= 0)
		set_leaves(sides[fort.side], fort.side_open, false)
		var ram := rams[fort.side]
		ram.visible = fort.ram_hp > 0
		ram.position.x = fort.ram_at.x
		ram.position.z = fort.ram_at.y
	for i in flags.size():
		var owner := mission.supply.points[i].owner
		var mat: StandardMaterial3D = flags[i].material_override
		mat.albedo_color = COLORS[owner].darkened(0.4) if owner >= 0 else Color.SLATE_GRAY
	marker.position.x = aim.x
	marker.position.z = aim.y
	marker.position.y = Terrain.height(aim) + 0.12
	camera.follow(mission.teams[0].leader, mission.field)
