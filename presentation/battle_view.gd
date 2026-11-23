class_name BattlefieldView extends Node3D
## 灰盒视图把模拟平面映射为三维 X/Z；角色、镜头与受击反馈只读战场状态。
var mission: BattleMission
var camera := Camera3D.new()
var models: Dictionary = {}
var observed_hits: Dictionary = {}
var gates: Array[MeshInstance3D] = []
var sides: Array[MeshInstance3D] = []
var rams: Array[MeshInstance3D] = []
var flags: Array[MeshInstance3D] = []
var marker: MeshInstance3D
const COLORS := [Color("#46c6dd"), Color("#ef886a")]
const STONE := Color("#92978d")

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
	label.position = Vector3(at.x, h, at.y)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.018
	label.font_size = 38
	add_child(label)

func build(current: BattleMission) -> void:
	mission = current
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-64, 28, 0)
	add_child(light)
	add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = 68
	camera.position = Vector3(0, 47, 29)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	block(Vector2.ZERO, Vector3(58, 0.2, 30), Color("#506955"), -0.3)
	block(Vector2.ZERO, Vector3(55, 0.07, 3), Color("#89785d"), -0.08)
	for fort in mission.field.forts:
		# 三段城墙和两个门洞与 BattleSpace 的通行范围一致。
		for segment in [Vector2(-14, -2), Vector2(2, 6), Vector2(10, 14)]:
			var center := Vector2(fort.gate.x, (segment.x + segment.y) / 2)
			block(center, Vector3(0.7, 1.7, segment.y - segment.x), STONE)
		gates.append(block(fort.gate, Vector3(0.6, 1.4, 4), Color.SADDLE_BROWN))
		sides.append(block(fort.gate + Vector2(0, BattleSpace.SIDE_Z), Vector3(0.6, 1.4, 4), Color.SADDLE_BROWN))
		rams.append(block(fort.yard(), Vector3(2.0, 0.8, 1.0), Color.PERU))
	for point in mission.supply.points:
		flags.append(block(point.at, Vector3(4.5, 0.09, 4.5), Color.SLATE_GRAY))
		caption(point.at, point.title)
	for team in mission.teams:
		for unit in team.units:
			var shape := Vector3(0.52, 1.0, 0.52)
			if unit == team.leader:
				shape = Vector3(0.85, 1.6, 0.85)
			elif unit.spec.ranged:
				shape = Vector3(0.43, 1.25, 0.43)
			models[unit] = block(unit.position, shape, COLORS[team.side])
			observed_hits[unit] = 0
	marker = block(Vector2.ZERO, Vector3(1.3, 0.12, 1.3), Color.GOLD, 0.15)
	refresh(Vector2.ZERO, 0.0)

func refresh(aim: Vector2, dt: float) -> void:
	for unit: BattleAgent in models:
		var model: MeshInstance3D = models[unit]
		model.visible = unit.alive()
		model.position.x = unit.position.x
		model.position.z = unit.position.y
		if unit.hits != observed_hits[unit]:
			observed_hits[unit] = unit.hits
			model.scale.y = 0.55
		model.scale.y = move_toward(model.scale.y, 1.0, dt * 3)
	for fort in mission.field.forts:
		gates[fort.side].visible = not fort.front_open()
		sides[fort.side].visible = not fort.side_open
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
	var leader := mission.teams[0].leader
	var focus := Vector2.ZERO if not leader.alive() else leader.position * 0.12
	camera.position.x = lerpf(camera.position.x, focus.x, minf(1, dt * 3))
	camera.size = move_toward(camera.size, 72 if not leader.alive() else 68, dt * 4)

func point_at(screen: Vector2) -> Vector2:
	var hit = Plane(Vector3.UP, 0).intersects_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen))
	if hit == null:
		return Vector2.ZERO
	return Vector2(hit.x, hit.z).clamp(-BattleSpace.LIMIT, BattleSpace.LIMIT)
