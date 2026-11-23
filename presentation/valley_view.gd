extends Node3D
## 根据模拟高度绘制河谷；配套工程的树、草和石头复用网格，批量提交植被。
const Terrain := preload("res://battle/terrain.gd")
const PINE := preload("res://presentation/assets/meadow/pine.obj")
const BROADLEAF := preload("res://presentation/assets/meadow/broadleaf.obj")
const GRASS := preload("res://presentation/assets/meadow/grass_clump.obj")
const BOULDER := preload("res://presentation/assets/meadow/boulder.obj")
const SOIL := preload("res://presentation/assets/meadow/ground.gdshader")
const LEAVES := preload("res://presentation/assets/meadow/foliage.gdshader")
const WATER := preload("res://presentation/assets/meadow/water.gdshader")

func surface(mesh: Mesh, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	add_child(node)
	return node

func build(terrain: Terrain) -> void:
	var base := PlaneMesh.new()
	base.size = Vector2(220, 150)
	base.subdivide_width = 219
	base.subdivide_depth = 149
	var arrays := base.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in vertices.size():
		var p := Vector2(vertices[i].x, vertices[i].z)
		vertices[i].y = Terrain.height(p)
		normals[i] = Vector3(Terrain.height(p-Vector2.RIGHT)-Terrain.height(p+Vector2.RIGHT), 2,
			Terrain.height(p-Vector2.DOWN)-Terrain.height(p+Vector2.DOWN)).normalized()
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var ground := ArrayMesh.new()
	ground.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var soil := ShaderMaterial.new()
	soil.shader = SOIL
	surface(ground, soil)
	var water := ShaderMaterial.new()
	water.shader = WATER
	var river := PlaneMesh.new()
	river.size = Vector2(220, 12)
	surface(river, water).position = Vector3(0, Terrain.WATER_Y, -14)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color("#898a79")
	for rock: Vector3 in Terrain.ROCKS:
		var node := surface(BOULDER, stone)
		node.position = Vector3(rock.x, Terrain.height(Vector2(rock.x, rock.y)), rock.y)
		node.scale = Vector3(rock.z, rock.z * 1.3, rock.z)
	var plants := ShaderMaterial.new()
	plants.shader = LEAVES
	var pines := PackedVector2Array()
	var oaks := PackedVector2Array()
	for i in terrain.trees.size():
		if i % 3 == 0:
			oaks.append(terrain.trees[i])
		else:
			pines.append(terrain.trees[i])
	var rng := RandomNumberGenerator.new()
	rng.seed = 3112
	var grass := PackedVector2Array()
	for i in 900:
		var p := Vector2(rng.randf_range(-61,61), rng.randf_range(-32,32))
		if absf(p.x) < 34 and absf(p.y) > 2.8 and absf(p.y-14) > 2 and absf(p.y-Terrain.river_z(p.x)) > 3:
			grass.append(p)
	batch(PINE, plants, pines, rng)
	batch(BROADLEAF, plants, oaks, rng)
	batch(GRASS, plants, grass, rng)

func batch(mesh: Mesh, material: Material, points: PackedVector2Array, rng: RandomNumberGenerator) -> void:
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.use_custom_data = true
	instances.mesh = mesh
	instances.instance_count = points.size()
	for i in points.size():
		var p := points[i]
		var basis := Basis(Vector3.UP, rng.randf_range(-PI, PI)).scaled(Vector3.ONE * rng.randf_range(0.78, 1.15))
		instances.set_instance_transform(i, Transform3D(basis, Vector3(p.x, Terrain.height(p), p.y)))
		instances.set_instance_custom_data(i, Color(rng.randf(), 0, 0, 1))
	var node := MultiMeshInstance3D.new()
	node.multimesh = instances
	node.material_override = material
	add_child(node)
