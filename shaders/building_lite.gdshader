shader_type spatial;
// 廢墟建築外牆（低畫質版）：只用一次雜湊運算畫出明暗與窗格，沒有雜訊 / 迴圈，手機與網頁的 GPU 負擔小很多。
// 實例參數名稱與完整版相同，建構程式不需分支。

instance uniform vec3 tint : source_color = vec3(0.34, 0.32, 0.30);
instance uniform float seed = 0.0;

varying vec3 v_world;
varying vec3 v_normal;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 col = tint;
	float emit = 0.0;
	if (abs(v_normal.y) < 0.5) {
		float u = abs(v_normal.x) > 0.5 ? v_world.z : v_world.x;
		float y = v_world.y;
		// 大塊明暗不均（取代昂貴的雜訊）
		col *= 0.78 + 0.4 * hash(floor(vec2(u, y) / 5.0) + seed);
		// 窗格：全碎 / 封板 / 髒玻璃 / 少數有火光
		vec2 cell = vec2(u / 2.4, y / 3.2);
		vec2 id = floor(cell);
		vec2 f = fract(cell);
		bool in_window = f.x > 0.2 && f.x < 0.8 && f.y > 0.25 && f.y < 0.78 && y > 2.2;
		if (in_window) {
			float h = hash(id + seed);
			if (h < 0.5) {
				col = vec3(0.014);
			} else if (h < 0.93) {
				col = vec3(0.05, 0.058, 0.064);
			} else {
				col = vec3(0.9, 0.5, 0.2);
				emit = 0.6;
			}
		}
		// 地面附近的泥污
		col = mix(col, vec3(0.1, 0.09, 0.07), (1.0 - smoothstep(0.0, 2.4, y)) * 0.5);
	} else if (v_normal.y > 0.5) {
		col = vec3(0.07, 0.07, 0.065);
	}
	ALBEDO = col;
	ROUGHNESS = 0.95;
	EMISSION = col * emit;
}
