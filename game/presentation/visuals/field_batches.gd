extends Node3D
## Uniform transform + pose batches. Capacity only grows when a batch fills.
var groups := {}
var material := ShaderMaterial.new()

func _init() -> void:
	var shader := Shader.new()
	shader.code = """shader_type spatial;
	varying vec3 cloth_color;
	void vertex() { cloth_color = INSTANCE_CUSTOM.rgb; }
	void fragment() { ALBEDO = mix(COLOR.rgb, cloth_color, COLOR.a); ROUGHNESS = .88; }"""
	material.shader = shader

func add_group(key: String, mesh: Mesh, surface: Material = null) -> void:
	var geometry := MultiMesh.new()
	geometry.transform_format = MultiMesh.TRANSFORM_3D
	geometry.use_custom_data = true
	geometry.mesh = mesh
	var node := MultiMeshInstance3D.new()
	node.multimesh = geometry
	node.material_override = surface if surface != null else material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	groups[key] = {"geometry":geometry, "transforms":[], "colors":[]}

func begin_frame() -> void:
	for g: Dictionary in groups.values():
		g.transforms.clear()
		g.colors.clear()

func push(key: String, transform3: Transform3D, color: Color) -> void:
	var g: Dictionary = groups[key]
	g.transforms.append(transform3)
	g.colors.append(color.srgb_to_linear())

func flush() -> void:
	for g: Dictionary in groups.values():
		var m: MultiMesh = g.geometry
		var count: int = g.transforms.size()
		if m.instance_count < count:
			m.instance_count = maxi(8,ceili(count*1.3))
		m.visible_instance_count = count
		for i in count:
			m.set_instance_transform(i,g.transforms[i])
			m.set_instance_custom_data(i,g.colors[i])
