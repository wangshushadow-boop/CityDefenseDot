class_name SoldierView extends Node3D
## 兵种模型共用移动动画，服色表示阵营。动作只读取模拟位置和受击次数。
const GENERAL := preload("res://presentation/assets/polyfork/general.glb")
const INFANTRY := preload("res://presentation/assets/polyfork/spear_soldier.glb")
const RANGED := preload("res://presentation/assets/polyfork/crossbowman.glb")
const Terrain := preload("res://battle/terrain.gd")
var motion: AnimationPlayer
var figure: Node3D
var last_hits := 0

func build(unit: BattleAgent, leader: bool, uniform: Material) -> void:
	var scene := INFANTRY
	if leader:
		scene = GENERAL
	elif unit.spec.ranged:
		scene = RANGED
	figure = scene.instantiate()
	add_child(figure)
	var tunic := figure.find_child("garment-tunic", true, false) as MeshInstance3D
	tunic.material_override = uniform
	motion = figure.get_node("AnimationPlayer")
	motion.play(&"Idle")
	position = Vector3(unit.position.x, Terrain.height(unit.position), unit.position.y)
	rotation.y = PI / 2 if unit.side == 0 else -PI / 2
	scale = Vector3.ONE * (1.0 if leader else 0.83)

func sync(unit: BattleAgent, dt: float) -> void:
	visible = unit.alive()
	if not visible:
		if motion.is_playing():
			motion.stop()
		return
	var next := Vector3(unit.position.x, Terrain.height(unit.position), unit.position.y)
	var direction := next - position
	var clip := &"Idle"
	if direction.length_squared() > 0.000001 and dt > 0:
		rotation.y = atan2(direction.x, direction.z)
		clip = &"Run" if direction.length() > 3.5 * dt else &"Walk"
	elif unit.target != null and unit.target.alive():
		var offset := unit.target.position - unit.position
		if offset.length_squared() > 0.000001:
			rotation.y = atan2(offset.x, offset.y)
	if motion.current_animation != clip:
		motion.play(clip, 0.12)
	position = next
	if unit.hits != last_hits:
		last_hits = unit.hits
		figure.rotation.x = -0.18
	figure.rotation.x = move_toward(figure.rotation.x, 0, dt * 1.8)
