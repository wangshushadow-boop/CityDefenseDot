extends Node3D
## Scenery only. The BASE scene owns the navigation and collision surfaces.
const PALETTE := [Color("#ad3624"),Color("#24678b")]

func mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = .92
	return m

func prop(mesh: Mesh, m: Material, at: Vector3, parent: Node3D = self) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = m
	node.position = at
	parent.add_child(node)
	return node

func _ready() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#7eabc2")
	sky_mat.sky_horizon_color = Color("#e6dbc2")
	sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
	sky_mat.sun_angle_max = 8.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#e2daca")
	env.ambient_light_energy = .53
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color("#c5c4a8")
	env.fog_density = .0013
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("#ffe6bd")
	sun.light_energy = 1.27
	sun.rotation_degrees = Vector3(-48,-38,0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 85
	add_child(sun)
	var meadow := PlaneMesh.new()
	meadow.size = Vector2(880,660)
	var ground := ShaderMaterial.new()
	ground.shader = preload("res://presentation/visuals/field_ground.gdshader")
	prop(meadow,ground,Vector3(0,-.018,0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 241124
	var hill := SphereMesh.new()
	hill.radial_segments = 12
	hill.rings = 5
	hill.radius = 1
	hill.height = 2
	var ridge := mat(Color("#668674"))
	for i in 36:
		var a := TAU*i/36.0
		var n := prop(hill,ridge,Vector3(cos(a)*233,-4,sin(a)*174))
		n.scale = Vector3(rng.randf_range(36,65),rng.randf_range(12,33),rng.randf_range(24,54))
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var crown := CylinderMesh.new()
	crown.top_radius = 0
	crown.bottom_radius = 1.40
	crown.height = 3.3
	crown.radial_segments = 6
	var pines := MultiMesh.new()
	pines.transform_format = MultiMesh.TRANSFORM_3D
	pines.use_colors = true
	pines.mesh = crown
	pines.instance_count = 480
	var pine_mat := mat(Color.WHITE)
	pine_mat.vertex_color_use_as_albedo = true
	pine_mat.vertex_color_is_srgb = true
	for i in 240:
		var x := rng.randf_range(-146,146)
		var z := rng.randf_range(84,111)*(1 if i%2 else -1)
		var factor := rng.randf_range(.7,1.8)
		var tree_color := Color("#294634").lerp(Color("#58714e"),rng.randf())
		var base := Basis(Vector3.UP,rng.randf_range(0,TAU)).scaled(Vector3.ONE*factor)
		pines.set_instance_transform(i*2,Transform3D(base,Vector3(x,2.15*factor,z)))
		pines.set_instance_color(i*2,tree_color)
		pines.set_instance_transform(i*2+1,Transform3D(base.scaled(Vector3.ONE*.78),Vector3(x,3.48*factor,z)))
		pines.set_instance_color(i*2+1,tree_color.lightened(.09))
	var forest := MultiMeshInstance3D.new()
	forest.multimesh = pines
	forest.material_override = pine_mat
	add_child(forest)
	for side in 2:
		for z in [-13,12]:
			banner(Vector3(-52 if side == 0 else 52,0,z),side)

func banner(at: Vector3, side: int) -> void:
	var standard := Node3D.new()
	standard.position = at
	add_child(standard)
	var shaft := CylinderMesh.new()
	shaft.bottom_radius = .065
	shaft.top_radius = .049
	shaft.height = 5.2
	shaft.radial_segments = 8
	prop(shaft,mat(Color("#6c4a2b")),Vector3.UP*2.6,standard)
	var bar := BoxMesh.new()
	bar.size = Vector3(1.52,.09,.09)
	prop(bar,mat(Color("#b99b59")),Vector3(0,4.9,0),standard)
	var cloth := BoxMesh.new()
	cloth.size = Vector3(1.27,2.28,.035)
	prop(cloth,mat(PALETTE[side]),Vector3(0,3.63,0),standard)
	var trim := BoxMesh.new()
	trim.size = Vector3(1.27,.10,.055)
	var gilt := mat(Color("#e5bd72"))
	prop(trim,gilt,Vector3(0,4.65,0),standard)
	prop(trim,gilt,Vector3(0,2.65,0),standard)
	var seal := BoxMesh.new()
	seal.size = Vector3(.44,.44,.056)
	prop(seal,gilt,Vector3(0,3.81,0),standard).rotation.z = PI*.25
