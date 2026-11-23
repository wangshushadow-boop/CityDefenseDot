extends Camera3D
## 统领存活时使用肩后透视镜头。阵亡后切换至全图指挥，军令仍交给本方阵营。
const Terrain := preload("res://battle/terrain.gd")
var yaw := 0.0
var pitch := 0.14
var overview := false
var first_person := false
var zoom := false
var distance := 3.2
var free_yaw := 0.0
var free_pitch := 0.0
var free_look := false
var locked: BattleAgent

func orbit(relative: Vector2) -> void:
	if not overview:
		if free_look:
			free_yaw = wrapf(free_yaw + relative.x * 0.003, -PI, PI)
			free_pitch = clampf(pitch + free_pitch + relative.y * 0.003, -1.25, 1.25) - pitch
			return
		if locked == null:
			yaw = wrapf(yaw + relative.x * 0.003, -PI, PI)
		pitch = clampf(pitch + relative.y * 0.003, -1.25, 1.25)

func movement(axis: Vector2) -> Vector2:
	var forward := Vector2.from_angle(yaw)
	return (axis.x * Vector2(-forward.y, forward.x) - axis.y * forward).limit_length()

func track_target(unit: BattleAgent, field: BattleSpace) -> void:
	if locked == null:
		return
	if not unit.alive() or not locked.alive() or unit.position.distance_to(locked.position) > 18 or not field.clear_line(unit.position, locked.position):
		locked = null
	else:
		yaw = (locked.position - unit.position).angle()

func follow(unit: BattleAgent, field: BattleSpace) -> void:
	overview = not unit.alive()
	if overview:
		projection = PROJECTION_ORTHOGONAL
		keep_aspect = KEEP_WIDTH
		size = maxf(128.0, 80.0 * get_viewport().get_visible_rect().size.aspect())
		position = Vector3(0, 95, 51)
		look_at(Vector3.ZERO)
		return
	projection = PROJECTION_PERSPECTIVE
	keep_aspect = KEEP_HEIGHT
	fov = 38 if zoom else 65
	var front := Vector2.from_angle(yaw + (free_yaw if free_look else 0.0))
	var side := Vector2(-front.y, front.x)
	var head_height := 1.50 + unit.manual.elevation
	if unit.manual.crouching:
		head_height -= CommanderCombat.CROUCH_DROP
	var eye := Vector3(unit.position.x, Terrain.height(unit.position) + head_height, unit.position.y)
	var shoulder := eye + Vector3(side.x, 0, side.y) * 0.48
	var angle := pitch + (free_pitch if free_look else 0.0)
	var back := Vector3(-front.x * cos(angle), sin(angle), -front.y * cos(angle))
	if first_person:
		position = eye + Vector3(front.x, 0, front.y) * 0.13
		look_at(position - back)
		return
	var desired := shoulder + back * distance
	# 由肩向后探测，在墙、岩石和山坡前收短镜头。
	position = eye
	for i in range(1, 17):
		var sample := eye.lerp(desired, i / 16.0)
		var at := Vector2(sample.x, sample.z)
		if sample.y < Terrain.height(at) + 0.18 or not field.clear_line(unit.position, at):
			break
		position = sample
	look_at(position - back)

func ground_point(screen: Vector2) -> Variant:
	var origin := project_ray_origin(screen)
	var ray := project_ray_normal(screen)
	# 指挥目标取地形表面的首个交点，射向天空或地图外时保留上次选点。
	var last := origin
	for i in range(1, 500):
		var sample := origin + ray * (0.5 * i)
		var at := Vector2(sample.x, sample.z)
		if sample.y <= Terrain.height(at):
			if absf(at.x) > Terrain.LIMIT.x or absf(at.y) > Terrain.LIMIT.y:
				return null
			var t := clampf((last.y - Terrain.height(at)) / maxf(0.001, last.y - sample.y), 0, 1)
			var hit := last.lerp(sample, t)
			return Vector2(hit.x, hit.z)
		last = sample
	return null
