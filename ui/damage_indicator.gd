extends Control
# 受擊方向指示：在準星周圍以紅色弧線標出攻擊來源方向，隨視角轉動即時更新並淡出

const LIFE: float = 1.4

var hits: Array = []        # [世界座標, 已經過時間]
var player: Node3D = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_PAUSABLE


func add_hit(world_pos: Vector3) -> void:
	hits.append([world_pos, 0.0])
	if hits.size() > 6:
		hits.pop_front()


func _process(delta: float) -> void:
	if hits.is_empty():
		return
	for h in hits:
		h[1] += delta
	hits = hits.filter(func(h: Array) -> bool: return h[1] < LIFE)
	queue_redraw()


func _draw() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var f := -cam.global_transform.basis.z
	f.y = 0.0
	f = f.normalized()
	var r := cam.global_transform.basis.x
	r.y = 0.0
	r = r.normalized()
	var c := size * 0.5
	var radius := minf(size.x, size.y) * 0.3
	for h in hits:
		var to: Vector3 = (h[0] as Vector3) - cam.global_position
		to.y = 0.0
		if to.length() < 0.5:
			continue   # 貼身攻擊不標方向
		to = to.normalized()
		var ang := atan2(to.dot(r), to.dot(f)) - PI * 0.5   # 0 = 正前方（畫面上方）
		var k := 1.0 - float(h[1]) / LIFE
		var col := Color(1.0, 0.12, 0.1, 0.85 * k)
		draw_arc(c, radius, ang - 0.32, ang + 0.32, 14, col, 6.0 + 8.0 * k)
		draw_arc(c, radius + 12.0, ang - 0.22, ang + 0.22, 10, Color(1.0, 0.5, 0.4, 0.5 * k), 3.0)
