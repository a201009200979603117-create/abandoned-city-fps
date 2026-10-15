extends SceneTree
# 無頭模式冒煙測試：godot --headless --path . -s tests/smoke.gd

var frames: int = 0
var main: Node
var game: Node
var logged_wave: int = 0


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	game = root.get_node("Game")


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 5:
		game.set_state(game.State.PLAYING)
		print("[test] 遊戲開始，state=", game.state)

	if frames > 5 and game.state == game.State.PLAYING:
		var player: Node3D = root.get_node("Main/Player")
		var enemies := get_nodes_in_group("enemies")
		# 讓玩家無敵並自動擊殺最近敵人，快速走完所有波次
		player.health = player.max_health
		player.global_position = Vector3(0, 0, 0)
		for e in enemies:
			if e.global_position.distance_to(player.global_position) < 30.0 or frames % 20 == 0:
				e.take_damage(1000.0)
		if game.wave != logged_wave:
			logged_wave = game.wave
			print("[test] 第 ", game.wave, " 波開始，敵人剩餘=", game.enemies_remaining, " 場上=", enemies.size())

	if frames > 5 and game.state != game.State.PLAYING and game.state != game.State.MENU:
		print("[test] 結束 state=", game.state, " 分數=", game.score, " 擊殺=", game.kills, " frames=", frames)
		quit(0)
		return true
	if frames > 20000:
		print("[test] 逾時 wave=", game.wave, " state=", game.state)
		quit(1)
		return true
	return false
