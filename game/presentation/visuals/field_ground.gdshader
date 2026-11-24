shader_type spatial;
render_mode cull_back, specular_disabled;

varying vec2 world_xz;

float noise_cell(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	vec2 k = vec2(51.27, 173.41);
	return mix(mix(fract(sin(dot(i,k))*2453.5), fract(sin(dot(i+vec2(1,0),k))*2453.5),f.x),
		mix(fract(sin(dot(i+vec2(0,1),k))*2453.5),fract(sin(dot(i+vec2(1,1),k))*2453.5),f.x),f.y);
}

void vertex() { world_xz = (MODEL_MATRIX * vec4(VERTEX,1.0)).xz; }
void fragment() {
	float patches = noise_cell(world_xz * .12) * .6 + noise_cell(world_xz * .43) * .4;
	float grass = noise_cell(world_xz * vec2(3.1,8.0));
	vec3 sod = mix(vec3(.14,.205,.084), vec3(.36,.40,.19), patches);
	float trail = 1.0 - smoothstep(.6,3.1,abs(world_xz.y-4.3*sin(world_xz.x*.031)-1.2*patches));
	ALBEDO = mix(sod,vec3(.40,.32,.18),trail*.65) * (.88 + grass*.19);
	ROUGHNESS = .96;
}
