shader_type spatial;
// 荒廢的地面/柏油路：龜裂、補丁、積水坑、碎石與泥土。以世界座標計算，路面與地面共用。

uniform vec3 base_color : source_color = vec3(0.16, 0.16, 0.15);
uniform float asphalt = 0.0;   // 1 = 柏油路（裂縫與積水更明顯）

varying vec3 v_world;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.07 + vec2(11.0, 5.0);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_world.xz;
	vec3 col = base_color;

	float big = fbm(p * 0.09);
	col *= 0.55 + big * 0.9;
	col *= 0.85 + vnoise(p * 7.0) * 0.3;          // 顆粒
	col *= 0.9 + vnoise(p * 28.0) * 0.2;

	// 泥土與灰燼漫過路面
	float dirt = smoothstep(0.5, 0.78, fbm(p * 0.17 + 40.0));
	col = mix(col, vec3(0.13, 0.1, 0.075), dirt * 0.65);

	// 雜草與苔蘚從裂縫與邊緣冒出
	float weeds = smoothstep(0.6, 0.82, fbm(p * 0.45 + 90.0));
	col = mix(col, vec3(0.11, 0.15, 0.06), weeds * (0.35 + 0.35 * asphalt));

	// 龜裂：兩層網狀細線
	float c1 = abs(vnoise(p * 0.55) - 0.5);
	float c2 = abs(vnoise(p * 1.4 + 7.0) - 0.5);
	float crack = (1.0 - smoothstep(0.0, 0.018, c1)) + (1.0 - smoothstep(0.0, 0.012, c2)) * 0.7;
	col *= 1.0 - clamp(crack, 0.0, 1.0) * (0.55 + 0.25 * asphalt);

	// 積水坑
	float pud = smoothstep(0.64, 0.7, fbm(p * 0.12 + 13.0));
	col = mix(col, vec3(0.025, 0.03, 0.035), pud * 0.9);
	ROUGHNESS = mix(0.95, 0.06, pud);
	METALLIC = pud * 0.2;

	// 碎石點
	float rub = step(0.93, hash(floor(p * 5.0)));
	col = mix(col, col * 1.6 + 0.04, rub * 0.5);

	ALBEDO = col;
}
