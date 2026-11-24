extends RefCounted
## Near meshes retain the imported skeleton, equipment and gait clips. The same
## mesh and joint weights supply a small shared pose bank for distant units.
const FILES := {"infantry":"spear_soldier", "archer":"crossbowman", "cavalry":"general", "mount":"horse"}
const COLORS := [Color("#a73325"), Color("#276d98")]
const HORSE_SCALE := 0.43
const SADDLE_OFFSET := Vector3(0, .59, .039)
const DIRECTIONS := ["up","left","right","thrust"]
const POSES_PER_SET := 8
var scene: PackedScene
var role: String
var poses: Array[Mesh] = []
var vertex_paint := StandardMaterial3D.new()

class Figure:
	var root: Node3D
	var player: AnimationPlayer
	var skeleton: Skeleton3D
	var right: int
	var forearm: int
	var left_leg: int
	var right_leg: int
	var tunic: MeshInstance3D
	var weapon: MeshInstance3D
	var spare: MeshInstance3D
	var clip := ""

func load_model(kind: String, host: Node3D) -> bool:
	role = kind
	vertex_paint.vertex_color_use_as_albedo = true
	vertex_paint.vertex_color_is_srgb = true
	vertex_paint.roughness = .9
	var path := "res://content/base/field/models/%s.glb" % FILES[kind]
	if not ResourceLoader.exists(path):
		return false
	scene = load(path) as PackedScene
	if scene == null:
		return false
	var figure := instantiate(host)
	if figure.skeleton == null or figure.player == null:
		figure.root.free()
		return false
	var variants := 2 if role in ["cavalry","archer"] else 1
	for variant in variants:
		for frame in POSES_PER_SET:
			var phase := "Guard" if frame == 7 else ("Active" if frame >= 3 else "Ready")
			var direction: String = DIRECTIONS[clampi(frame-3,0,3)]
			pose(figure, float(frame) * 13.0, 0 if frame == 0 else 2.8, phase, direction,
				frame*13-1, role == "cavalry" and variant == 0, role == "archer" and variant == 0)
			poses.append(_bake(figure))
	figure.root.free()
	return true

func instantiate(host: Node3D) -> Figure:
	var f := Figure.new()
	f.root = scene.instantiate()
	host.add_child(f.root)
	if role == "mount":
		f.root.scale = Vector3.ONE * HORSE_SCALE
	else:
		# These imported materials omit the flag although every surface carries COLOR_0.
		for part: MeshInstance3D in f.root.find_children("*","MeshInstance3D",true,false):
			part.material_override = vertex_paint
	var players := f.root.find_children("*", "AnimationPlayer", true, false)
	var skeletons := f.root.find_children("*", "Skeleton3D", true, false)
	if players.is_empty() or skeletons.is_empty():
		return f
	f.player = players[0]
	f.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	f.skeleton = skeletons[0]
	f.right = f.skeleton.find_bone("RightArm")
	f.forearm = f.skeleton.find_bone("RightForeArm")
	f.left_leg = f.skeleton.find_bone("LeftUpLeg")
	f.right_leg = f.skeleton.find_bone("RightUpLeg")
	f.tunic = f.root.find_child("garment-tunic", true, false) as MeshInstance3D
	if role == "archer":
		f.weapon = f.root.find_child("attach-righthand-mesh",true,false) as MeshInstance3D
		# Alternative melee slot follows the same hand as the imported crossbow.
		var hand := BoneAttachment3D.new()
		f.skeleton.add_child(hand)
		hand.bone_name = "RightHand"
		f.spare = MeshInstance3D.new()
		var blade := BoxMesh.new()
		blade.size = Vector3(.055, .035, .60)
		f.spare.mesh = blade
		f.spare.position.z = .22
		hand.add_child(f.spare)
	return f

func pose(f: Figure, time: float, speed: float, phase: String, direction: String, since: int,
		mounted: bool, ranged: bool) -> void:
	var clip := "Idle"
	if speed > .12 and not mounted:
		clip = ("Gallop" if role == "mount" else "Run") if speed > 3.3 else "Walk"
	if f.clip != clip:
		f.player.play(clip)
		f.clip = clip
	var duration := f.player.get_animation(clip).length
	f.player.seek(fposmod(time / 60.0, maxf(duration, .01)), true)
	if f.right < 0:
		return
	if f.weapon:
		f.weapon.visible = ranged
		f.spare.visible = not ranged
	if mounted:
		for joint in [f.left_leg, f.right_leg]:
			var sign_x := -1 if joint == f.left_leg else 1
			f.skeleton.set_bone_pose_rotation(joint, f.skeleton.get_bone_rest(joint).basis.get_rotation_quaternion()
				* Quaternion(Vector3.RIGHT, -.67) * Quaternion(Vector3.BACK, sign_x*.24))
	if phase not in ["Windup","Hold","Guard","Active","Recovery","Stagger"]:
		return
	var elapsed := maxf(0.0, time-since)
	var arm := Quaternion.IDENTITY
	var bend := 0.0
	if phase == "Guard":
		arm = Quaternion(Vector3.RIGHT, -.65) * Quaternion(Vector3.BACK, .75)
		bend = -.55
	elif phase == "Stagger":
		arm = Quaternion(Vector3.BACK, -.38)
	else:
		var sweep := -.78
		match phase:
			"Windup": sweep *= clampf(elapsed / 3.0, 0, 1)
			"Active": sweep = lerpf(-.78, 1.15, clampf((elapsed+.5)/2.0, 0, 1))
			"Recovery": sweep = 1.15 * (1.0-clampf(elapsed/3.0,0,1))
		match direction:
			"left": arm = Quaternion(Vector3.UP, sweep) * Quaternion(Vector3.BACK, -.66)
			"right": arm = Quaternion(Vector3.UP, -sweep) * Quaternion(Vector3.BACK, -.66)
			"up": arm = Quaternion(Vector3.RIGHT, sweep) * Quaternion(Vector3.BACK, -1.1)
			"thrust":
				arm = Quaternion(Vector3.UP, -1.20) * Quaternion(Vector3.BACK, -.45)
				bend = -.7 + sweep*.55
	f.skeleton.set_bone_pose_rotation(f.right, f.skeleton.get_bone_pose_rotation(f.right)*arm)
	f.skeleton.set_bone_pose_rotation(f.forearm, f.skeleton.get_bone_pose_rotation(f.forearm)*Quaternion(Vector3.UP,bend))

static func saddle_offset(f: Figure) -> Vector3:
	if f == null: return SADDLE_OFFSET
	var chest := f.skeleton.find_bone("Torso2")
	if chest < 0: return SADDLE_OFFSET
	var local := f.root.global_transform.affine_inverse() * f.skeleton.global_transform * f.skeleton.get_bone_global_pose(chest)
	# Saddle leather sits .22 m above the spine. Human hips sit .81 m above the root.
	return local.origin * HORSE_SCALE + Vector3.UP * (.22-.81)

func _bake(f: Figure) -> Mesh:
	var bake := SurfaceTool.new()
	bake.begin(Mesh.PRIMITIVE_TRIANGLES)
	f.skeleton.force_update_all_bone_transforms()
	var root_xform := f.root.get_parent_node_3d().global_transform.affine_inverse()
	for part: MeshInstance3D in f.root.find_children("*", "MeshInstance3D", true, false):
		if part.mesh == null or not part.is_visible_in_tree():
			continue
		var mesh_xform := root_xform * part.global_transform
		var binds: Array[Transform3D] = []
		if part.skin:
			for b in part.skin.get_bind_count():
				var joint := f.skeleton.find_bone(part.skin.get_bind_name(b))
				if joint < 0:
					joint = part.skin.get_bind_bone(b)
				binds.append(f.skeleton.get_bone_global_pose(joint) * part.skin.get_bind_pose(b))
		for surface in part.mesh.get_surface_count():
			var a := part.mesh.surface_get_arrays(surface)
			var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			var posed := PackedVector3Array()
			var directions := PackedVector3Array()
			posed.resize(verts.size())
			directions.resize(verts.size())
			var weights: Variant = a[Mesh.ARRAY_WEIGHTS]
			var bones: Variant = a[Mesh.ARRAY_BONES]
			for i in verts.size():
				var v := verts[i]
				var n := normals[i]
				if weights != null and not binds.is_empty():
					v = Vector3.ZERO
					n = Vector3.ZERO
					var stride: int = weights.size()/verts.size()
					for j in stride:
						var w: float = weights[i*stride+j]
						if w > 0:
							var bind := binds[int(bones[i*stride+j])]
							v += (bind * verts[i])*w
							n += (bind.basis * normals[i])*w
				posed[i] = mesh_xform * v
				directions[i] = (mesh_xform.basis*n).normalized()
			var tint := Color.WHITE
			var mat := part.mesh.surface_get_material(surface) as StandardMaterial3D
			if mat:
				tint = mat.albedo_color.srgb_to_linear()
			var colors: Variant = a[Mesh.ARRAY_COLOR]
			var indices: Variant = a[Mesh.ARRAY_INDEX]
			var total: int = indices.size() if indices != null else verts.size()
			for j in total:
				var i: int = indices[j] if indices != null else j
				var col: Color = colors[i].srgb_to_linear()*tint if colors != null else tint
				# Vertex alpha masks the cloth for the per-instance faction color.
				col.a = 1.0 if part == f.tunic else 0.0
				bake.set_color(col)
				bake.set_normal(directions[i])
				bake.add_vertex(posed[i])
	bake.index()
	return bake.commit()
