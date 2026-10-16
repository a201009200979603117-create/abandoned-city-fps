shader_type spatial;
// 廢墟建築外牆：以世界座標程序化繪製——剝落的水泥與裸露紅磚、爆裂/封板的窗戶、煙燻、雨痕、鏽跡與裂縫。
// 單一材質供所有建築共用以降低 draw call。

instance uniform vec3 tint : source_color = vec3(0.34, 0.32, 0.30);
instance uniform float seed = 0.0;

varying vec3 v_world;
varying vec3 v_normal;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.0, 9.0);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 col = tint;
	float emit = 0.0;
	float rough = 0.95;

	if (abs(v_normal.y) < 0.5) {
		float u = abs(v_normal.x) > 0.5 ? v_world.z : v_world.x;
		float y = v_world.y;
		vec2 uv = vec2(u, y) + seed;

		// 基底：髒污水泥，大尺度明暗不均
		float blotch = fbm(uv * 0.35);
		float fine = vnoise(uv * 6.0);
		col *= 0.62 + blotch * 0.55;
		col *= 0.92 + fine * 0.14;

		// 灰泥剝落，露出紅磚
		float peel = fbm(uv * 0.55 + 31.0);
		if (peel > 0.62) {
			vec2 b = vec2(u / 0.42 + floor(y / 0.14) * 0.5, y / 0.14);
			vec2 bf = fract(b);
			float mortar = (bf.x < 0.06 || bf.y < 0.1) ? 1.0 : 0.0;
			vec3 brick = vec3(0.34, 0.14, 0.1) * (0.7 + hash(floor(b) + seed) * 0.6);
			brick = mix(brick, vec3(0.22, 0.2, 0.18), mortar);
			col = mix(col, brick, smoothstep(0.62, 0.66, peel));
		}

		// 窗格
		vec2 cell = vec2(u / 2.4, y / 3.2);
		vec2 id = floor(cell);
		vec2 f = fract(cell);
		bool in_window = f.x > 0.2 && f.x < 0.8 && f.y > 0.25 && f.y < 0.78 && y > 2.2;
		float h = hash(id + seed);
		if (in_window) {
			vec2 wl = vec2((f.x - 0.2) / 0.6, (f.y - 0.25) / 0.53);
			float frame = (wl.x < 0.07 || wl.x > 0.93 || wl.y < 0.06 || wl.y > 0.94) ? 1.0 : 0.0;
			if (h < 0.34) {
				// 玻璃全碎：漆黑的室內，邊緣殘留玻璃尖角
				col = vec3(0.012, 0.012, 0.014);
				float shard = step(0.5, vnoise(wl * 9.0 + h * 40.0)) * step(wl.y, 0.25 + 0.2 * vnoise(vec2(wl.x * 7.0, h * 9.0)));
				col = mix(col, vec3(0.1, 0.12, 0.13), shard * 0.8);
				rough = 0.2;
			} else if (h < 0.5) {
				// 木板封窗
				float plank = fract(wl.y * 5.0 + h);
				col = vec3(0.17, 0.12, 0.08) * (0.6 + vnoise(vec2(wl.x * 3.0, wl.y * 24.0 + h * 10.0)) * 0.7);
				col *= plank < 0.06 ? 0.3 : 1.0;
			} else if (h < 0.93) {
				// 殘存的髒玻璃
				col = vec3(0.045, 0.055, 0.06) * (0.7 + fbm(wl * 3.0 + h * 20.0) * 0.8);
				rough = 0.25;
				if (wl.x + wl.y * 0.6 > 0.9 && wl.x + wl.y * 0.6 < 1.05) {
					col += vec3(0.04);
				}
			} else {
				// 有人落腳：微弱搖曳的火光
				col = vec3(0.9, 0.5, 0.2);
				emit = 0.55 + 0.25 * sin(TIME * 7.0 + h * 80.0) * sin(TIME * 3.1 + h * 20.0);
			}
			if (frame > 0.5) {
				col = vec3(0.07, 0.065, 0.06);
				emit = 0.0;
				rough = 0.9;
			}
		} else {
			// 窗下水痕與窗上煙燻
			float sill = f.x > 0.15 && f.x < 0.85 ? 1.0 : 0.0;
			if (y > 2.2) {
				float streak = fbm(vec2(u * 4.5, y * 0.35) + seed);
				if (f.y < 0.25) {
					col *= 1.0 - 0.45 * sill * streak;
				}
				if (f.y > 0.78 && f.y < 0.98) {
					col *= 1.0 - 0.5 * sill * (0.5 + 0.5 * vnoise(vec2(u * 3.0, y * 2.0)));
				}
			}
			if (f.y < 0.06) {
				col *= 0.7;
			}
		}

		// 爆炸/火災留下的大片燻黑
		float soot = smoothstep(0.55, 0.8, fbm(uv * 0.22 + 70.0));
		col = mix(col, col * 0.28, soot * 0.85);

		// 地面附近：泥污與苔蘚
		float ground = 1.0 - smoothstep(0.0, 2.6, y);
		col = mix(col, vec3(0.1, 0.09, 0.07), ground * (0.35 + 0.4 * vnoise(uv * 2.0)));
		float moss = ground * smoothstep(0.55, 0.8, fbm(uv * 1.3 + 5.0));
		col = mix(col, vec3(0.1, 0.17, 0.07), moss * 0.55);

		// 裂縫
		float crack_n = vnoise(vec2(u * 0.8 + sin(y * 0.9) * 0.6, y * 0.18) + seed * 3.0);
		float crack = 1.0 - smoothstep(0.0, 0.025, abs(crack_n - 0.5));
		col *= 1.0 - crack * 0.7;

		// 鏽水
		float rust = smoothstep(0.7, 0.9, vnoise(vec2(u * 2.2, y * 0.12) + seed * 5.0));
		col = mix(col, vec3(0.28, 0.13, 0.06), rust * 0.35);
	} else if (v_normal.y > 0.5) {
		// 屋頂：焦黑瀝青與積水坑
		vec2 uv = v_world.xz * 0.5 + seed;
		col = vec3(0.07, 0.07, 0.065) * (0.7 + fbm(uv * 2.0) * 0.8);
		float puddle = smoothstep(0.62, 0.7, fbm(uv * 0.8));
		col = mix(col, vec3(0.03, 0.035, 0.04), puddle);
		rough = mix(0.9, 0.1, puddle);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	EMISSION = col * emit;
}
