extends SceneTree
# 無頭模式冒煙測試：
#   T_MODE=zombie T_LEVEL=3 godot --headless --path . -s tests/smoke.gd   （殭屍關卡第 3 關）
#   T_MODE=br godot --headless --path . -s tests/smoke.gd                  （大逃殺）
# 殭屍模式：自動選技能、施放全部技能、擊殺所有敵人直到勝利
# 大逃殺：讓 AI 互相交戰一段時間，之後逐一淘汰剩餘 AI，確認奪冠、空投、結算流程

var frames: int = 0
var main: Node
var game: Node
var save: Node
var mode: String = "zombie"
var level: int = 1
var logged_wave: int = 0
var picks: int = 0
var br_kill_timer: int = 0
var br_phase_log: int = 0
var airdrop_done: bool = false


func _initialize() -> void:
	# 以環境變數指定：T_MODE=zombie|br　T_LEVEL=1..10
	if OS.get_environment("T_MODE") != "":
		mode = OS.get_environment("T_MODE")
	if OS.get_environment("T_LEVEL") != "":
		level = int(OS.get_environment("T_LEVEL"))
	# 自動載入在 _initialize 之後才就緒，主場景延到第 2 幀再建立
	pass


func _start_main() -> void:
	game = root.get_node("Game")
	save = root.get_node("Save")
	game.mode = mode
	game._apply_level(level)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 2:
		_start_main()
		return false
	if main == null:
		return false
	var hud: Node = main.get_node("UI")
	if frames == 5:
		hud._begin_run()
		print("[test] 模式=", mode, " 關卡=", level, " 波數=", game.total_waves, " state=", game.state)

	if game.state == game.State.SKILL:
		picks += 1
		hud._pick_skill(0)

	if mode == "br":
		return _br_step()
	return _zombie_step()


func _finish() -> bool:
	print("[test] 結束 state=", game.state, " 分數=", game.score, " 擊殺=", game.kills, " 喪屍幣=", game.run_coins, " 名次=", game.last_rank, " 結算=", game.result, " 空投=", game.airdrop_item, " frames=", frames)
	quit(0)
	return true


func _zombie_step() -> bool:
	if frames > 5 and game.state == game.State.PLAYING:
		var player: Node3D = root.get_node("Main/Player")
		var enemies := get_nodes_in_group("enemies")
		player.health = player.max_health
		player.global_position = Vector3(0, 0, 0)
		var skills: Node = main.get_node("Skills")
		if frames % 30 == 0:
			for id in ["shockwave", "heal", "grenade", "freeze", "frenzy"]:
				skills.cast(id)
		for e in enemies:
			if e.global_position.distance_to(player.global_position) < 30.0 or frames % 20 == 0:
				e.take_damage(1000.0)
		if game.wave != logged_wave:
			logged_wave = game.wave
			print("[test] 第 ", game.wave, " 波開始，場上=", enemies.size())

	if frames > 5 and game.state != game.State.PLAYING and game.state != game.State.MENU and game.state != game.State.SKILL:
		return _finish()
	if frames > 150000:
		print("[test] 逾時 wave=", game.wave, " state=", game.state)
		quit(1)
		return true
	return false


func _br_step() -> bool:
	var br: Node = main.get_node("BR")
	var player: Node3D = root.get_node("Main/Player")
	if frames > 5 and game.state == game.State.PLAYING and bool(br.started):
		# 玩家無敵，讓 AI 先交戰
		player.health = player.max_health
		if frames % 300 == 0:
			var guns := get_nodes_in_group("gun_pickups").size()
			var armed := 0
			for b in get_nodes_in_group("br_bots"):
				if b.has_weapon():
					armed += 1
			print("[test] frames=", frames, " 存活=", game.br_alive, " 有槍AI=", armed, " 地上槍=", guns, " 安全區=", snappedf(br.zone_radius, 0.1), " ", br.zone_text())
		# 600 幀之後開始逐一淘汰剩餘 AI
		if frames > 1500 and not br.victory:
			br_kill_timer += 1
			if br_kill_timer % 40 == 0:
				var bots := get_nodes_in_group("br_bots")
				if bots.size() > 0:
					bots[0].take_damage(9999.0, player)
		if br.victory and br.airdrop != null and br.airdrop.is_landed() and not airdrop_done:
			airdrop_done = true
			print("[test] 空投著陸，開啟")
			br.airdrop.open()

	if frames > 5 and game.state != game.State.PLAYING and game.state != game.State.MENU:
		return _finish()
	if frames > 12000:
		print("[test] 逾時 state=", game.state, " 存活=", game.br_alive)
		quit(1)
		return true
	return false
