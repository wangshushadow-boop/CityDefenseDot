extends RefCounted

# Procedural original fixtures. Rest positions are in model metres.
const HUMAN_JOINTS = [
	Vector3(0, 0.88, 0), Vector3(0, 1.15, 0), Vector3(0, 1.54, 0),
	Vector3(-0.23, 1.43, 0), Vector3(0.23, 1.43, 0),
	Vector3(-0.12, 0.88, 0), Vector3(0.12, 0.88, 0)]
const HORSE_JOINTS = [
	Vector3(0, 0.96, 0), Vector3(0, 1.1, -0.48), Vector3(0, 1.50, -0.72),
	Vector3(-0.20, 0.89, -0.39), Vector3(0.20, 0.89, -0.39),
	Vector3(-0.20, 0.89, 0.40), Vector3(0.20, 0.89, 0.40)]
const PARENTS = [-1, 0, 1, 0, 0, 0, 0]
const SIDES = 12
const RINGS = 8
var horse: bool
var mesh: ArrayMesh
var skin: Skin

func _init(is_horse: bool):
	horse = is_horse
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	if horse:
		ellipsoid(surface, Vector3(0, 1.05, 0), Vector3(.33, .40, .71), 0)
		ellipsoid(surface, Vector3(0, 1.36, -.54), Vector3(.18, .42, .21), 1)
		ellipsoid(surface, Vector3(0, 1.62, -.83), Vector3(.17, .18, .31), 2)
		for i in range(3, 7):
			ellipsoid(surface, HORSE_JOINTS[i] + Vector3.DOWN * .40, Vector3(.08, .48, .10), i)
	else:
		ellipsoid(surface, Vector3(0, 1.19, 0), Vector3(.24, .37, .15), 1)
		ellipsoid(surface, Vector3(0, 1.64, 0), Vector3(.14, .19, .14), 2)
		for i in range(3, 7):
			var leg := i >= 5
			var length_y := .45 if leg else .30
			ellipsoid(surface, HUMAN_JOINTS[i] + Vector3.DOWN * length_y * .85,
				Vector3(.085, length_y, .10), i)
		ellipsoid(surface, Vector3(.23, .94, -.22), Vector3(.04, .05, .34), 4)
	surface.index()
	mesh = surface.commit()
	var template := skeleton()
	skin = template.create_skin_from_rest_transforms()
	template.free()

func ellipsoid(surface: SurfaceTool, center: Vector3, scale3: Vector3, bone: int):
	for ring in RINGS:
		for side in SIDES:
			for corner in [Vector2i(0,0), Vector2i(1,0), Vector2i(1,1),
					Vector2i(0,0), Vector2i(1,1), Vector2i(0,1)]:
				var latitude := PI * ((ring + int(corner.y)) / float(RINGS) - .5)
				var angle := TAU * (side + int(corner.x)) / SIDES
				var n := Vector3(cos(latitude) * cos(angle), sin(latitude), cos(latitude) * sin(angle))
				var parent := maxi(0, PARENTS[bone])
				var blend := .18 * maxf(0, n.y)
				surface.set_bones(PackedInt32Array([bone, parent, 0, 0]))
				surface.set_weights(PackedFloat32Array([1-blend, blend, 0, 0]))
				surface.set_normal((n / scale3).normalized())
				surface.add_vertex(center + n * scale3)

func skeleton() -> Skeleton3D:
	var sk := Skeleton3D.new()
	var joints: Array = HORSE_JOINTS if horse else HUMAN_JOINTS
	for i in joints.size():
		sk.add_bone("joint_%d" % i)
		var origin: Vector3 = joints[i]
		if PARENTS[i] >= 0:
			sk.set_bone_parent(i, PARENTS[i])
			origin -= Vector3(joints[PARENTS[i]])
		sk.set_bone_rest(i, Transform3D(Basis.IDENTITY, origin))
	sk.reset_bone_poses()
	return sk

func spawn(parent: Node3D, material: Material) -> Skeleton3D:
	var sk := skeleton()
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.skin = skin
	visual.skeleton = NodePath("..")
	visual.material_override = material
	sk.add_child(visual)
	parent.add_child(sk)
	return sk
