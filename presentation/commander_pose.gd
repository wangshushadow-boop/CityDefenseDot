extends SkeletonModifier3D
## 在步行动画后叠加持剑、举盾和腿部动作，武器挂点跟随同一副骨架。
var fighter: CommanderCombat
var unit: BattleAgent
var right_arm: int
var left_arm: int
var forearm: int
var leg: int
var knee: int
var left_leg: int
var left_knee: int
var sword: BoneAttachment3D
var shield: BoneAttachment3D

func bind(actor: BattleAgent, skeleton: Skeleton3D) -> void:
	unit = actor
	fighter = actor.manual
	right_arm = skeleton.find_bone("RightArm")
	left_arm = skeleton.find_bone("LeftArm")
	forearm = skeleton.find_bone("RightForeArm")
	leg = skeleton.find_bone("RightUpLeg")
	knee = skeleton.find_bone("RightLeg")
	left_leg = skeleton.find_bone("LeftUpLeg")
	left_knee = skeleton.find_bone("LeftLeg")
	sword = mount(skeleton, "RightHand")
	piece(sword, BoxMesh.new(), Vector3(0.055, 0.68, 0.032), Vector3(0,0.46,0), Color.SILVER)
	piece(sword, BoxMesh.new(), Vector3(0.21, 0.045, 0.06), Vector3(0,0.105,0), Color.DARK_GOLDENROD)
	piece(sword, BoxMesh.new(), Vector3(0.055, 0.19, 0.05), Vector3.ZERO, Color.SADDLE_BROWN)
	shield = mount(skeleton, "LeftHand")
	var disk := CylinderMesh.new()
	disk.radial_segments = 12
	var face := piece(shield, disk, Vector3(0.58,0.04,0.65), Vector3(0,0,0.06), Color("#795139"))
	face.rotation.x = PI / 2

func mount(skeleton: Skeleton3D, bone: StringName) -> BoneAttachment3D:
	var anchor := BoneAttachment3D.new()
	skeleton.add_child(anchor)
	anchor.bone_name = bone
	return anchor

func piece(parent: Node3D, mesh: Mesh, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.scale = size
	node.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	node.material_override = material
	parent.add_child(node)
	return node

func _process_modification_with_delta(_dt: float) -> void:
	if fighter == null:
		return
	var sk := get_skeleton()
	sword.visible = fighter.drawn
	shield.visible = fighter.shield
	var pose := Vector3(0, 0.75, 0.72)
	if fighter.winding or fighter.swing_time > 0:
		var finish := Vector3(-0.25, 1.45, 0.4)
		match fighter.direction:
			CommanderCombat.Direction.LEFT:
				pose = Vector3(-0.25, 2.4, -0.3)
				finish.y = -0.25
			CommanderCombat.Direction.RIGHT:
				pose = Vector3(-0.1, -0.45, -0.4)
				finish.y = 2.5
			CommanderCombat.Direction.OVERHEAD:
				pose = Vector3(-0.65, 0.35, -1.85)
			CommanderCombat.Direction.THRUST:
				pose = Vector3(1.25, 0.32, 0.7)
				finish.x = 1.45
		if fighter.swing_time > 0:
			pose = pose.lerp(finish, smoothstep(0, 0.72, 1.0 - fighter.swing_time / CommanderCombat.SWING_DURATION))
	elif unit.guarding and not fighter.shield:
		match fighter.direction:
			CommanderCombat.Direction.LEFT: pose = Vector3(-0.35, 2.0, 0.3)
			CommanderCombat.Direction.RIGHT: pose = Vector3(-0.25, -0.15, -0.6)
			CommanderCombat.Direction.OVERHEAD: pose = Vector3(-0.65, 0.7, -1.5)
			CommanderCombat.Direction.THRUST: pose = Vector3(0.65, 1.1, 0.65)
	sk.set_bone_pose_rotation(right_arm, Quaternion.from_euler(pose))
	sk.set_bone_pose_rotation(forearm, Quaternion.from_euler(Vector3(0, 0.4, -0.35)))
	var guard := Vector3(0,-0.55,-0.65)
	if (unit.guarding and fighter.shield) or (fighter.bashing and fighter.kick_time > 0):
		guard = Vector3(0,-1.55, -0.1)
		match fighter.direction:
			CommanderCombat.Direction.OVERHEAD: guard.z = 0.75
			CommanderCombat.Direction.THRUST: guard.z = -0.65
			CommanderCombat.Direction.LEFT: guard.y += 0.55
			CommanderCombat.Direction.RIGHT: guard.y -= 0.55
		if fighter.kick_time > 0:
			guard.x += sin(PI * fighter.kick_time / 0.36) * 0.85
	sk.set_bone_pose_rotation(left_arm, Quaternion.from_euler(guard))
	if fighter.crouching:
		for thigh: int in [leg, left_leg]:
			sk.set_bone_pose_rotation(thigh, sk.get_bone_pose_rotation(thigh) * Quaternion(Vector3.RIGHT, -0.88))
		for shin: int in [knee, left_knee]:
			sk.set_bone_pose_rotation(shin, sk.get_bone_pose_rotation(shin) * Quaternion(Vector3.RIGHT, 1.74))
	if fighter.kick_time > 0 and not fighter.bashing:
		var phase := sin(PI * fighter.kick_time / 0.36)
		sk.set_bone_pose_rotation(leg, Quaternion(Vector3.RIGHT, -1.35 * phase))
		sk.set_bone_pose_rotation(knee, Quaternion(Vector3.RIGHT, 0.25 * phase))
