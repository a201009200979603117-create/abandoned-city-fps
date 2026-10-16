extends Control
# 大逃殺小地圖：顯示地圖範圍、目前/下一個安全區與玩家位置（不顯示 AI 玩家）

const HALF: float = 100.0

var player: Node3D
var manager: Node


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(170, 170)


func _process(_delta: float) -> void:
	queue_redraw()


func _to_map(p: Vector3) -> Vector2:
	var s := size.x / (HALF * 2.0)
	return Vector2((p.x + HALF) * s, (p.z + HALF) * s)


func _draw() -> void:
	if player == null:
		player = get_tree().get_first_node_in_group("player") as Node3D
	if manager == null:
		manager = get_node_or_null("/root/Main/BR")
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.07, 0.1, 0.72))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.7, 0.75, 0.85, 0.8), false, 2.0)
	var s := size.x / (HALF * 2.0)
	# 道路
	for axis in [-50.0, 0.0, 50.0]:
		var a: float = (float(axis) + HALF) * s
		draw_line(Vector2(a, 0), Vector2(a, size.y), Color(0.3, 0.3, 0.34, 0.8), 2.0)
		draw_line(Vector2(0, a), Vector2(size.x, a), Color(0.3, 0.3, 0.34, 0.8), 2.0)
	if manager != null and manager.get("zone_center") != null:
		var c: Vector3 = manager.zone_center
		draw_arc(_to_map(c), float(manager.zone_radius) * s, 0.0, TAU, 48, Color(0.3, 0.6, 1.0, 0.95), 2.0)
		if not bool(manager.zone_finished):
			var nc: Vector3 = manager.next_center
			draw_arc(_to_map(nc), float(manager.next_radius) * s, 0.0, TAU, 40, Color(1.0, 1.0, 1.0, 0.9), 1.5)
	if player != null:
		var pos := _to_map(player.global_position)
		var yaw: float = player.global_rotation.y
		# 玩家朝向：前方為 -Z
		var fwd := Vector2(-sin(yaw), -cos(yaw))
		var right := Vector2(-fwd.y, fwd.x)
		draw_colored_polygon(PackedVector2Array([pos + fwd * 8.0, pos - fwd * 5.0 + right * 5.0, pos - fwd * 5.0 - right * 5.0]), Color(1.0, 0.85, 0.2))
