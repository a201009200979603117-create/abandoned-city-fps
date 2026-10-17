extends SceneTree
# 無頭測試：連續射擊、瞄準、換彈，確認特效物件池不會洩漏節點、沒有腳本錯誤
#   godot --headless --path . -s tests/shoot_check.gd

var frames: int = 0
var main: Node
var nodes_before: int = 0


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 2:
		var game := root.get_node("Game")
		game.mode = "zombie"
		game._apply_level(1)
		game.skip_menu = true
		main = load("res://main.tscn").instantiate()
		root.add_child(main)
		current_scene = main
	elif frames == 5:
		pass
	elif frames > 10 and frames < 700:
		var weapon: Node = main.get_node("Player/Head/Camera3D/Weapon")
		if frames == 60:
			nodes_before = count_nodes()
		weapon.fire_timer = 0.0
		weapon.current_ammo = 30
		weapon.reload_left = 0.0
		weapon.shoot()
		weapon.touch_zoom = (frames / 100) % 2 == 0
		weapon.player.rotation.y += 0.01
	elif frames == 700:
		print("[shoot] 節點數 開始=", nodes_before, " 結束=", count_nodes())
		quit(0 if count_nodes() - nodes_before < 40 else 1)
	return false


func count_nodes() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
