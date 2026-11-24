extends NavigationRegion3D

func _ready() -> void:
	# Two sides of a plaza share the shorter centre edge with a 1 m wide passage.
	# Tessellate the passage to keep navigation triangles well conditioned.
	var vertices := PackedVector3Array([
		Vector3(-1200,0,-1600), Vector3(-1200,0,0), Vector3(-0.5,0,0), Vector3(-0.5,0,-1600),
		Vector3(0.5,0,0), Vector3(0.5,0,-1600), Vector3(1200,0,0), Vector3(1200,0,-1600)])
	var polygons := [[0,1,2,3], [3,2,4,5], [5,4,6,7]]
	var left := 2
	var right := 4
	for z in range(8, 1201, 8):
		var next := vertices.size()
		vertices.append(Vector3(-0.5, 0, z))
		vertices.append(Vector3(0.5, 0, z))
		polygons.append([left, next, next + 1, right])
		left = next
		right = next + 1
	var mesh := NavigationMesh.new()
	mesh.vertices = vertices
	for poly in polygons:
		mesh.add_polygon(PackedInt32Array(poly))
	navigation_mesh = mesh
