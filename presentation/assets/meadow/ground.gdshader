shader_type spatial;
// 以世界坐标生成草甸与土路，保证地形分块或镜头移动时纹理稳定。
varying vec3 ground;
float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise2(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i+vec2(1,0)), f.x), mix(hash2(i+vec2(0,1)), hash2(i+1.0), f.x), f.y);
}
void vertex() { ground = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = ground.xz;
	float patch = noise2(p * 0.21) * 0.64 + noise2(p * 1.7) * 0.36;
	vec3 meadow = mix(vec3(0.13,0.21,0.075), vec3(0.36,0.40,0.16), patch);
	float lane = min(abs(p.y), abs(p.y-14.0)+0.6);
	float ford_path = abs(abs(p.x)-18.0) + max(0.0,p.y) + max(0.0,-22.0-p.y);
	lane = min(lane, ford_path+0.6);
	float road = 1.0-smoothstep(1.6,2.7,lane + 0.9*(patch-0.5));
	vec3 soil = mix(vec3(0.34,0.24,0.14),vec3(0.51,0.40,0.25),patch);
	float shore = 1.0-smoothstep(1.8,3.6,abs(p.y+14.0-2.8*cos(p.x*0.085)));
	ALBEDO = mix(mix(meadow,soil,max(shore*0.8,road)),vec3(0.28,0.30,0.24)*(0.8+patch*0.4),smoothstep(4.0,13.0,ground.y));
	ROUGHNESS = 0.98;
}
