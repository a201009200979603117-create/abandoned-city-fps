extends Control
# 封面美術：以程式繪製的末日夜景（月亮、城市天際線、霧氣、殭屍剪影、飄動火星）

var t: float = 0.0
var layers: Array = []      # 每層：[建築陣列, 顏色, 視差速度, 是否亮窗]
var stars: Array = []
var embers: Array = []
var zombies: Array = []
var lamp_x: Array = []
var built_size: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	if size.x < 10.0 or size.y < 10.0:
		return
	built_size = size
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var w := size.x
	var h := size.y
	var horizon := h * 0.72

	stars.clear()
	for i in 90:
		stars.append(Vector3(rng.randf() * w, rng.randf() * horizon * 0.7, rng.randf() * TAU))

	layers.clear()
	var specs := [
		[Color(0.3, 0.13, 0.2), 4.0, 0.34, 0.5, 14.0, false],
		[Color(0.2, 0.09, 0.15), 7.0, 0.26, 0.42, 22.0, true],
		[Color(0.11, 0.055, 0.1), 11.0, 0.2, 0.34, 34.0, true],
		[Color(0.035, 0.025, 0.045), 16.0, 0.13, 0.26, 52.0, false],
	]
	for spec in specs:
		var buildings: Array = []
		var x := -60.0
		while x < w + 120.0:
			var bw: float = rng.randf_range(w * 0.04, w * 0.1)
			var bh: float = h * rng.randf_range(float(spec[2]) * 0.55, float(spec[2]) * 1.15)
			# 第三項：樓頂樣式 0 平頂 1 天線 2 斜角
			var lit: Array = []
			if spec[5]:
				var cols := int(bw / 14.0)
				var rows := int(bh / 20.0)
				for cx in cols:
					for cy in rows:
						if rng.randf() < 0.07:
							lit.append(Vector3(cx, cy, rng.randf() * TAU))
			buildings.append([x, bw, bh, rng.randi() % 3, lit])
			x += bw + rng.randf_range(0.0, 6.0)
		layers.append([buildings, spec[0], spec[1], spec[5]])

	embers.clear()
	for i in 46:
		embers.append([rng.randf() * w, rng.randf() * h, rng.randf_range(10.0, 36.0), rng.randf_range(1.0, 2.6), rng.randf() * TAU])

	zombies.clear()
	for i in 7:
		var zx := w * rng.randf_range(0.5, 0.98)
		var sc := rng.randf_range(0.8, 1.3) * h / 720.0
		zombies.append([zx, sc, rng.randf() * TAU, rng.randf_range(-0.2, 0.2)])

	lamp_x = [w * 0.12, w * 0.56, w * 0.9]


func _process(delta: float) -> void:
	t += delta
	for e in embers:
		e[0] += sin(t * 0.8 + e[4]) * 8.0 * delta
		e[1] -= e[2] * delta
		if e[1] < -10.0:
			e[1] = size.y + 10.0
			e[0] = randf() * size.x
	queue_redraw()


func _draw() -> void:
	if size != built_size:
		_rebuild()
	var w := size.x
	var h := size.y
	var horizon := h * 0.72

	# 夜空漸層
	var sky := PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, horizon), Vector2(0, horizon)])
	var sky_cols := PackedColorArray([Color(0.02, 0.02, 0.08), Color(0.02, 0.02, 0.08), Color(0.7, 0.2, 0.12), Color(0.7, 0.2, 0.12)])
	draw_polygon(sky, sky_cols)
	# 地平線紅色光暈
	for i in 6:
		var a := 0.07 - float(i) * 0.01
		draw_rect(Rect2(0, horizon - h * (0.05 + 0.05 * i), w, h * 0.05), Color(0.9, 0.25, 0.1, a))

	# 星星
	for s in stars:
		var tw := 0.4 + 0.6 * absf(sin(t * 1.3 + s.z))
		draw_circle(Vector2(s.x, s.y), 1.2, Color(1, 1, 1, 0.5 * tw))

	# 月亮與光暈
	var moon := Vector2(w * 0.74, h * 0.22)
	var mr := h * 0.085
	for i in 16:
		draw_circle(moon, mr * (1.2 + 0.22 * i), Color(0.95, 0.75, 0.55, 0.032))
	draw_circle(moon, mr, Color(0.98, 0.9, 0.75))
	draw_circle(moon + Vector2(-mr * 0.3, -mr * 0.2), mr * 0.2, Color(0.88, 0.78, 0.62))
	draw_circle(moon + Vector2(mr * 0.35, mr * 0.25), mr * 0.14, Color(0.88, 0.78, 0.62))
	draw_circle(moon + Vector2(mr * 0.1, -mr * 0.5), mr * 0.1, Color(0.9, 0.8, 0.65))

	# 天際線（由遠到近）
	var li := 0
	for layer in layers:
		var buildings: Array = layer[0]
		var col: Color = layer[1]
		var drift := sin(t * 0.15 + li) * float(layer[2]) * 0.7
		for b in buildings:
			var bx: float = float(b[0]) + drift
			var bw: float = b[1]
			var bh: float = b[2]
			var top := horizon - bh + li * 6.0
			var base_y := horizon + li * 10.0 + 40.0
			draw_rect(Rect2(bx, top, bw, base_y - top), col)
			match int(b[3]):
				1:
					draw_rect(Rect2(bx + bw * 0.5 - 1.0, top - 22.0, 2.0, 22.0), col)
					if li >= 1:
						draw_circle(Vector2(bx + bw * 0.5, top - 22.0), 2.2, Color(1.0, 0.1, 0.1, 0.4 + 0.6 * absf(sin(t * 2.0 + bx))))
				2:
					draw_colored_polygon(PackedVector2Array([Vector2(bx, top), Vector2(bx + bw, top), Vector2(bx + bw, top - 14.0)]), col)
			if layer[3]:
				for lw in b[4]:
					var flick := 0.55 + 0.45 * sin(t * (1.5 + fmod(lw.z, 2.0)) + lw.z * 3.0)
					if flick > 0.15:
						draw_rect(Rect2(bx + 5.0 + lw.x * 14.0, top + 8.0 + lw.y * 20.0, 6.0, 9.0), Color(1.0, 0.72, 0.3, 0.85 * flick))
		li += 1

	# 霧氣
	for i in 5:
		var fy := horizon - h * 0.04 + float(i) * h * 0.035
		var fx := fmod(t * (6.0 + i * 3.0) + i * 200.0, w + 600.0) - 300.0
		draw_circle(Vector2(fx, fy), h * 0.22, Color(0.55, 0.35, 0.4, 0.035))
		draw_circle(Vector2(w - fx * 0.8, fy + 10.0), h * 0.18, Color(0.5, 0.35, 0.4, 0.03))

	# 地面
	var ground := PackedVector2Array([Vector2(0, horizon + 28.0), Vector2(w, horizon + 28.0), Vector2(w, h), Vector2(0, h)])
	draw_polygon(ground, PackedColorArray([Color(0.06, 0.04, 0.06), Color(0.06, 0.04, 0.06), Color(0.01, 0.01, 0.02), Color(0.01, 0.01, 0.02)]))
	# 道路中線
	for i in 8:
		var ry := horizon + 50.0 + pow(float(i) / 8.0, 1.8) * (h - horizon)
		var rw := 6.0 + float(i) * 8.0
		draw_rect(Rect2(w * 0.5 - rw * 0.5, ry, rw, 3.0 + i * 1.5), Color(0.5, 0.42, 0.18, 0.28))

	# 路燈
	for lx in lamp_x:
		var base := Vector2(lx, h * 0.97)
		var tip := Vector2(lx, h * 0.62)
		draw_line(base, tip, Color(0.02, 0.02, 0.03), 5.0)
		draw_line(tip, tip + Vector2(26.0, -6.0), Color(0.02, 0.02, 0.03), 4.0)
		var flick := 1.0 if sin(t * 7.0 + lx) > -0.85 else 0.2
		var lamp := tip + Vector2(26.0, -2.0)
		for i in 5:
			draw_circle(lamp, 10.0 + 14.0 * i, Color(1.0, 0.7, 0.3, 0.05 * flick))
		draw_circle(lamp, 4.0, Color(1.0, 0.85, 0.5, flick))

	# 殭屍剪影
	for z in zombies:
		_draw_zombie(Vector2(z[0], h * 0.93), z[1], z[2], z[3])

	# 火星
	for e in embers:
		var a := 0.4 + 0.6 * absf(sin(t * 3.0 + e[4]))
		draw_circle(Vector2(e[0], e[1]), e[3], Color(1.0, 0.55, 0.15, a * 0.8))

	# 暗角
	var edge := 0.5
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w * 0.25, 0), Vector2(w * 0.25, h), Vector2(0, h)]),
		PackedColorArray([Color(0, 0, 0, edge), Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, edge)]))
	draw_polygon(PackedVector2Array([Vector2(w * 0.75, 0), Vector2(w, 0), Vector2(w, h), Vector2(w * 0.75, h)]),
		PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, edge), Color(0, 0, 0, edge), Color(0, 0, 0, 0)]))
	draw_polygon(PackedVector2Array([Vector2(0, h * 0.78), Vector2(w, h * 0.78), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.6), Color(0, 0, 0, 0.6)]))


func _draw_zombie(pos: Vector2, sc: float, phase: float, tilt: float) -> void:
	var col := Color(0.01, 0.008, 0.015)
	var sway := sin(t * 1.1 + phase) * 4.0 * sc
	var u := 100.0 * sc
	var hip := pos
	var shoulder := pos + Vector2(sway + tilt * u * 0.3, -u * 0.8)
	var head := shoulder + Vector2(sway * 0.6 + tilt * u * 0.2, -u * 0.22)
	# 腿
	draw_line(hip + Vector2(-u * 0.06, 0), hip + Vector2(-u * 0.1, u * 0.45), col, u * 0.11)
	draw_line(hip + Vector2(u * 0.06, 0), hip + Vector2(u * 0.12, u * 0.45), col, u * 0.11)
	# 軀幹
	draw_line(hip, shoulder, col, u * 0.3)
	# 伸向前方的手臂
	var arm_lift := sin(t * 1.7 + phase) * u * 0.04
	draw_line(shoulder, shoulder + Vector2(-u * 0.5, -u * 0.12 + arm_lift), col, u * 0.08)
	draw_line(shoulder, shoulder + Vector2(-u * 0.44, -u * 0.04 - arm_lift), col, u * 0.08)
	draw_circle(head, u * 0.13, col)
	# 發亮的雙眼
	var eye_a := 0.6 + 0.4 * sin(t * 2.5 + phase)
	draw_circle(head + Vector2(-u * 0.05, -u * 0.01), 2.2 * sc + 0.6, Color(1.0, 0.1, 0.1, eye_a))
	draw_circle(head + Vector2(u * 0.02, -u * 0.01), 2.2 * sc + 0.6, Color(1.0, 0.1, 0.1, eye_a))
