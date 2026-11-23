shader_type spatial;
render_mode cull_disabled;
// 参考工程的 OBJ 用 UV 横坐标区分树干、树叶、松针与草叶。
varying float variation;
void vertex() {
	variation = INSTANCE_CUSTOM.r;
	if (UV.x > 0.75) {
		VERTEX.x += sin(MODEL_MATRIX[3].x + TIME*1.6) * VERTEX.y * 0.12;
	}
}
void fragment() {
	vec3 col = vec3(0.21,0.13,0.065);
	if (UV.x > 0.75) { col = mix(vec3(0.17,0.25,0.07),vec3(0.38,0.39,0.15),variation); }
	else if (UV.x > 0.50) { col = mix(vec3(0.075,0.16,0.10),vec3(0.14,0.27,0.15),variation); }
	else if (UV.x > 0.25) { col = mix(vec3(0.15,0.29,0.085),vec3(0.49,0.33,0.085),variation); }
	ALBEDO = col * mix(0.78,1.14,UV.y);
	ROUGHNESS = 0.95;
}
