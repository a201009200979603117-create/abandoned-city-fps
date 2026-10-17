extends Control
# 向量圖示：以基本圖形繪製，不需要任何圖檔。用法：IconRect.make("gun", Color.WHITE, 32)

var kind: String = "play"
var color: Color = Color.WHITE


static func make(icon_kind: String, icon_color: Color = Color.WHITE, px: float = 30.0) -> Control:
	var r := new()
	r.kind = icon_kind
	r.color = icon_color
	r.custom_minimum_size = Vector2(px, px)
	r.size = Vector2(px, px)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _draw() -> void:
	var s := minf(size.x, size.y) * 0.5 * 0.9
	var c := size * 0.5
	var w := maxf(s * 0.16, 2.0)   # 線寬
	match kind:
		"play":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-0.55, -0.8) * s, c + Vector2(0.85, 0) * s, c + Vector2(-0.55, 0.8) * s]), color)
		"back":
			draw_polyline(PackedVector2Array([c + Vector2(0.4, -0.8) * s, c + Vector2(-0.5, 0) * s, c + Vector2(0.4, 0.8) * s]), color, w * 1.4)
		"gun":
			# 步槍側影：槍管、機匣、握把、彈匣、槍托
			draw_rect(Rect2(c + Vector2(-1.0, -0.28) * s, Vector2(0.55, 0.16) * s), color)
			draw_rect(Rect2(c + Vector2(-0.5, -0.4) * s, Vector2(1.1, 0.42) * s), color)
			draw_rect(Rect2(c + Vector2(0.55, -0.32) * s, Vector2(0.45, 0.5) * s), color)
			draw_rect(Rect2(c + Vector2(-0.05, 0.0) * s, Vector2(0.22, 0.75) * s), color)
			draw_rect(Rect2(c + Vector2(0.32, 0.0) * s, Vector2(0.2, 0.5) * s), color)
		"shield":
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -0.95) * s, c + Vector2(0.8, -0.65) * s, c + Vector2(0.75, 0.15) * s,
				c + Vector2(0, 0.98) * s, c + Vector2(-0.75, 0.15) * s, c + Vector2(-0.8, -0.65) * s]), color)
			draw_line(c + Vector2(0, -0.6) * s, c + Vector2(0, 0.55) * s, Color(0, 0, 0, 0.35), w)
		"dice":
			draw_rect(Rect2(c - Vector2(0.85, 0.85) * s, Vector2(1.7, 1.7) * s), color, false, w)
			for p in [Vector2(-0.4, -0.4), Vector2(0.4, -0.4), Vector2(0, 0), Vector2(-0.4, 0.4), Vector2(0.4, 0.4)]:
				draw_circle(c + p * s, s * 0.14, color)
		"trophy":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-0.6, -0.85) * s, c + Vector2(0.6, -0.85) * s, c + Vector2(0.45, 0.1) * s, c + Vector2(-0.45, 0.1) * s]), color)
			draw_arc(c + Vector2(-0.6, -0.5) * s, s * 0.32, PI * 0.5, PI * 1.5, 10, color, w)
			draw_arc(c + Vector2(0.6, -0.5) * s, s * 0.32, -PI * 0.5, PI * 0.5, 10, color, w)
			draw_rect(Rect2(c + Vector2(-0.12, 0.1) * s, Vector2(0.24, 0.5) * s), color)
			draw_rect(Rect2(c + Vector2(-0.5, 0.6) * s, Vector2(1.0, 0.25) * s), color)
		"gear":
			for k in 8:
				var a := float(k) * TAU / 8.0
				draw_line(c + Vector2.from_angle(a) * s * 0.55, c + Vector2.from_angle(a) * s * 0.98, color, w * 1.5)
			draw_arc(c, s * 0.6, 0.0, TAU, 28, color, w * 1.4)
			draw_circle(c, s * 0.22, color)
		"coin":
			draw_circle(c, s * 0.95, color)
			draw_circle(c, s * 0.62, Color(0, 0, 0, 0.28))
			draw_circle(c, s * 0.5, color)
		"mission":
			draw_rect(Rect2(c + Vector2(-0.7, -0.85) * s, Vector2(1.4, 1.75) * s), color, false, w)
			draw_rect(Rect2(c + Vector2(-0.3, -1.0) * s, Vector2(0.6, 0.3) * s), color)
			draw_polyline(PackedVector2Array([c + Vector2(-0.4, 0.05) * s, c + Vector2(-0.12, 0.35) * s, c + Vector2(0.45, -0.3) * s]), color, w)
			draw_line(c + Vector2(-0.4, 0.6) * s, c + Vector2(0.4, 0.6) * s, color, w * 0.8)
		"star":
			var pts := PackedVector2Array()
			for k in 10:
				var rr := s if k % 2 == 0 else s * 0.42
				pts.append(c + Vector2.from_angle(-PI * 0.5 + float(k) * TAU / 10.0) * rr)
			draw_colored_polygon(pts, color)
		"skull":
			draw_circle(c + Vector2(0, -0.15) * s, s * 0.78, color)
			draw_rect(Rect2(c + Vector2(-0.42, 0.4) * s, Vector2(0.84, 0.5) * s), color)
			draw_circle(c + Vector2(-0.32, -0.15) * s, s * 0.2, Color(0, 0, 0, 0.75))
			draw_circle(c + Vector2(0.32, -0.15) * s, s * 0.2, Color(0, 0, 0, 0.75))
			draw_line(c + Vector2(-0.14, 0.45) * s, c + Vector2(-0.14, 0.88) * s, Color(0, 0, 0, 0.5), w * 0.7)
			draw_line(c + Vector2(0.14, 0.45) * s, c + Vector2(0.14, 0.88) * s, Color(0, 0, 0, 0.5), w * 0.7)
		"crosshair":
			draw_arc(c, s * 0.62, 0.0, TAU, 28, color, w)
			draw_circle(c, s * 0.12, color)
			for k in 4:
				var d := Vector2.from_angle(float(k) * PI * 0.5)
				draw_line(c + d * s * 0.62, c + d * s * 1.0, color, w)
		"user":
			draw_circle(c + Vector2(0, -0.4) * s, s * 0.38, color)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-0.8, 0.9) * s, c + Vector2(-0.6, 0.2) * s, c + Vector2(0.6, 0.2) * s, c + Vector2(0.8, 0.9) * s]), color)
		"lock":
			draw_rect(Rect2(c + Vector2(-0.6, -0.1) * s, Vector2(1.2, 0.95) * s), color)
			draw_arc(c + Vector2(0, -0.1) * s, s * 0.4, PI, TAU, 14, color, w)
		"check":
			draw_polyline(PackedVector2Array([c + Vector2(-0.7, 0.05) * s, c + Vector2(-0.2, 0.55) * s, c + Vector2(0.75, -0.55) * s]), color, w * 1.5)
		"wrench":
			draw_line(c + Vector2(-0.6, 0.6) * s, c + Vector2(0.35, -0.35) * s, color, w * 1.8)
			draw_arc(c + Vector2(0.45, -0.45) * s, s * 0.38, 0.6, TAU - 0.6, 14, color, w * 1.4)
		_:
			draw_circle(c, s * 0.5, color)
