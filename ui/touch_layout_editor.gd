extends Control
# 觸控按鍵位置編輯器：拖曳圓形按鍵即可調整，位置存於 Save.touch_layout。
# 版面計算與遊戲內的 TouchControls 共用，所見即所得。

const TouchControls = preload("res://ui/touch_controls.gd")
const UIUtil = preload("res://ui/ui_util.gd")

var drag_id: String = ""
var drag_off: Vector2 = Vector2.ZERO
var insets: Vector4 = Vector4.ZERO
var u: float = 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_update_layout)
	_update_layout.call_deferred()


func _update_layout() -> void:
	insets = UIUtil.safe_insets(self)
	u = clampf(size.y / 648.0, 0.8, 1.25)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			var best := ""
			var best_d := INF
			for b in TouchControls.BUTTONS:
				var c := TouchControls.button_pos(b, size, insets, u)
				var d := c.distance_to(mb.position)
				if d <= TouchControls.button_radius(b, u) * 1.25 and d < best_d:
					best_d = d
					best = b["id"]
					drag_off = c - mb.position
			drag_id = best
		else:
			if drag_id != "":
				Save.save()
			drag_id = ""
		queue_redraw()
	elif event is InputEventMouseMotion and drag_id != "":
		var mm := event as InputEventMouseMotion
		for b in TouchControls.BUTTONS:
			if b["id"] == drag_id:
				var np := (mm.position + drag_off).clamp(Vector2(24, 24), size - Vector2(24, 24))
				Save.touch_layout[drag_id] = TouchControls.offsets_from_pos(b, np, size, insets, u)
		queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	# 示意背景：天空 / 地面與準星
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.10, 0.09, 0.12))
	draw_rect(Rect2(0, size.y * 0.55, size.x, size.y * 0.45), Color(0.07, 0.06, 0.07))
	draw_line(Vector2(0, size.y * 0.55), Vector2(size.x, size.y * 0.55), Color(0.3, 0.25, 0.3), 2.0)
	draw_arc(size * 0.5, 14.0, 0.0, TAU, 20, Color(1, 1, 1, 0.5), 2.0)
	draw_line(size * 0.5 + Vector2(-24, 0), size * 0.5 + Vector2(-8, 0), Color(1, 1, 1, 0.5), 2.0)
	draw_line(size * 0.5 + Vector2(8, 0), size * 0.5 + Vector2(24, 0), Color(1, 1, 1, 0.5), 2.0)
	# 安全區框線
	draw_rect(Rect2(Vector2(insets.x, insets.y), size - Vector2(insets.x + insets.z, insets.y + insets.w)), Color(1, 1, 1, 0.08), false, 2.0)

	var a := Save.touch_opacity / 0.85
	# 搖桿示意
	var sh := Vector2(insets.x + 190.0 * u, size.y - insets.w - 150.0 * u)
	if Save.left_handed:
		sh = Vector2(size.x - insets.z - 190.0 * u, size.y - insets.w - 150.0 * u)
	draw_arc(sh, TouchControls.STICK_RADIUS * u, 0.0, TAU, 40, Color(1, 1, 1, 0.3 * a), 3.0)
	draw_circle(sh, 34.0 * u, Color(1, 1, 1, 0.15 * a))
	draw_string(font, sh + Vector2(-22, 6), "搖桿", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.6))
	# 暫停鈕示意
	var pp := Vector2(insets.x + 34.0 * u, insets.y + 34.0 * u)
	draw_arc(pp, 26.0 * u, 0.0, TAU, 28, Color(1, 1, 1, 0.5 * a), 2.5)
	draw_string(font, pp + Vector2(-17, 6), "暫停", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.7))

	for b in TouchControls.BUTTONS:
		var c := TouchControls.button_pos(b, size, insets, u)
		var r := TouchControls.button_radius(b, u)
		var active: bool = b["id"] == drag_id
		var col := Color(1.0, 0.45, 0.3) if str(b["id"]).begins_with("fire") else Color(1, 1, 1)
		if bool(b.get("br", false)):
			col = Color(0.6, 0.95, 0.55)
		draw_circle(c, r, Color(col.r, col.g, col.b, (0.35 if active else 0.16) * a))
		draw_arc(c, r, 0.0, TAU, 36, Color(col.r, col.g, col.b, (1.0 if active else 0.75) * a), 3.0)
		var fs := clampi(int(r * 0.42), 13, 24)
		var label := str(b["name"])
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, c + Vector2(-w * 0.5, fs * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.95))
		if bool(b.get("br", false)):
			draw_string(font, c + Vector2(-14, r + 14), "大逃殺", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.95, 0.55, 0.8))
