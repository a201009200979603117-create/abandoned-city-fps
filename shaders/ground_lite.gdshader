shader_type spatial;
// 荒廢地面 / 柏油路（低畫質版）：只用兩次雜湊運算做出大塊明暗與顆粒，沒有雜訊 / 迴圈。

uniform vec3 base_color : source_color = vec3(0.16, 0.16, 0.15);
uniform float asphalt = 0.0;

varying vec3 v_world;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_world.xz;
	vec3 col = base_color;
	col *= 0.62 + hash(floor(p * 0.12)) * 0.75;      // 大塊明暗
	col *= 0.88 + hash(floor(p * 5.0)) * 0.24;       // 顆粒
	ROUGHNESS = 0.95;
	ALBEDO = col;
}
