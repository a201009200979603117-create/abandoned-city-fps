shader_type canvas_item;
// 螢幕空間動態模糊：沿視角轉動方向做方向模糊，衝刺時加上由中心向外的放射模糊

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform vec2 vel = vec2(0.0);
uniform float radial = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - vec2(0.5);
	// 畫面邊緣模糊較強、中心較清晰，保留準心周圍的可讀性
	float edge = smoothstep(0.05, 0.6, length(c));
	vec2 d = vel * mix(0.45, 1.0, edge) + c * radial * edge;
	vec3 sum = vec3(0.0);
	for (int i = 0; i < 8; i++) {
		float t = float(i) / 7.0 - 0.5;
		sum += textureLod(screen_tex, clamp(uv + d * t, vec2(0.001), vec2(0.999)), 0.0).rgb;
	}
	COLOR = vec4(sum / 8.0, 1.0);
}
