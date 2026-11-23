shader_type spatial;
// 水面位于河床上方，浅滩底色较亮，细小波纹顺河谷运动。
varying vec2 river;
void vertex() { river = (MODEL_MATRIX*vec4(VERTEX,1.0)).xz; }
void fragment() {
	float shallows = 1.0-smoothstep(2.3,3.4,abs(abs(river.x)-18.0));
	float lines = sin(river.y*8.0 + sin(river.x*1.9 - TIME)*0.7 + TIME*1.5);
	ALBEDO = mix(vec3(0.055,0.26,0.29), vec3(0.26,0.43,0.33), shallows) + 0.045*smoothstep(0.68,1.0,lines);
	ROUGHNESS = 0.34;
}
