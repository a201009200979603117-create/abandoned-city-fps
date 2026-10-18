extends SceneTree
# 觸控模擬測試：在桌機以注入 InputEventScreenTouch / Drag 模擬手機操作
#   AC_SAVE=<獨立存檔> T_MODE=br|zombie godot --path . -s tests/touch_check.gd

var tc: Control = null
var game: Node
var mode: String = "zombie"


func _touch(idx: int, pos: Vector2, pressed: bool) -> void:
	var t := InputEventScreenTouch.new()
	t.index = idx
	t.position = pos
	t.pressed = pressed
	Input.parse_input_event(t)


func _drag(idx: int, pos: Vector2, rel: Vector2) -> void:
	var d := InputEventScreenDrag.new()
	d.index = idx
	d.position = pos
	d.relative = rel
	Input.parse_input_event(d)


func _btn(id: String) -> Vector2:
	for b in tc.BUTTONS:
		if b["id"] == id:
			return tc._button_pos(b)
	return Vector2.ZERO


func _init() -> void:
	await process_frame
	mode = OS.get_environment("T_MODE") if OS.get_environment("T_MODE") != "" else "zombie"
	root.get_node("Save").touch_mode = true
	game = root.get_node("Game")
	change_scene_to_file("res://main.tscn")
	await create_timer(1.0).timeout
	game.begin_run(mode, 1)
	await create_timer(2.0).timeout
	var main := root.get_node("Main")
	if mode == "zombie":
		main.get_node("UI")._pick_skill(0)
		await create_timer(0.5).timeout
	for c in main.get_node("UI").get_children():
		if c.get_script() != null and str(c.get_script().resource_path).ends_with("touch_controls.gd"):
			tc = c
	print("touch controls found: ", tc != null, " size ", tc.size, " state ", game.state)
	var player := main.get_node("Player")
	var weapon := player.get_node("Head/Camera3D/Weapon")
	if mode == "br":
		# 等落地
		var t0 := Time.get_ticks_msec()
		while player.skydiving and Time.get_ticks_msec() - t0 < 60000:
			_touch(9, _btn("jump"), true)
			await create_timer(0.2).timeout
			_touch(9, _btn("jump"), false)
			await create_timer(1.0).timeout
		print("BR landed, alt ", player.global_position.y)
		player.add_item("grenade", 2)
		player.add_item("medkit", 1)
	# 搖桿：左下按住拖曳（往前）
	var start := Vector2(200, tc.size.y - 200)
	_touch(0, start, true)
	await create_timer(0.1).timeout
	_drag(0, start + Vector2(0, -100), Vector2(0, -100))
	await create_timer(1.0).timeout
	var p1: Vector3 = player.global_position
	_touch(0, start + Vector2(0, -100), false)
	print("moved: ", p1.distance_to(Vector3.ZERO) > 0.1, " pos ", p1)
	# 轉視角
	var yaw0: float = player.rotation.y
	_touch(1, Vector2(tc.size.x * 0.6, 300), true)
	_drag(1, Vector2(tc.size.x * 0.6 + 80, 300), Vector2(80, 0))
	await create_timer(0.1).timeout
	_touch(1, Vector2(tc.size.x * 0.6 + 80, 300), false)
	print("look changed: ", absf(player.rotation.y - yaw0) > 0.01)
	# 射擊（按住）+ 左手射擊
	var ammo0: int = weapon.current_ammo
	_touch(2, _btn("fire"), true)
	await create_timer(0.6).timeout
	_touch(2, _btn("fire"), false)
	_touch(3, _btn("fire2"), true)
	await create_timer(0.4).timeout
	_touch(3, _btn("fire2"), false)
	print("fired: ", weapon.current_ammo < ammo0 or not weapon.armed, " ammo ", ammo0, "->", weapon.current_ammo)
	# 射擊鍵拖曳轉視角（按住射擊同時滑動）
	var yaw1: float = player.rotation.y
	var ammo1: int = weapon.current_ammo
	_touch(7, _btn("fire"), true)
	_drag(7, _btn("fire") + Vector2(-90, 0), Vector2(-90, 0))
	await create_timer(0.3).timeout
	_touch(7, _btn("fire") + Vector2(-90, 0), false)
	print("fire-drag look changed: ", absf(player.rotation.y - yaw1) > 0.01, " fired: ", weapon.current_ammo < ammo1 or not weapon.armed)
	# 奔跑中射擊
	_touch(0, start, true)
	_drag(0, start + Vector2(0, -200), Vector2(0, -200))
	await create_timer(0.8).timeout
	var ammo2: int = weapon.current_ammo
	_touch(8, _btn("fire"), true)
	await create_timer(0.5).timeout
	print("sprinting=", player.is_sprinting, " fired while sprinting: ", weapon.current_ammo < ammo2 or not weapon.armed)
	_touch(8, _btn("fire"), false)
	_touch(0, start + Vector2(0, -200), false)
	# 跳躍 / 蹲下 / 開鏡 / 換彈 / 拾取
	for id in ["jump", "crouch", "aim", "reload", "interact", "crouch", "aim"]:
		_touch(4, _btn(id), true)
		await create_timer(0.15).timeout
		_touch(4, _btn(id), false)
		await create_timer(0.15).timeout
	print("buttons ok, crouching=", player.crouching)
	if mode == "br":
		var g0: int = player.grenades
		_touch(5, _btn("grenade"), true)
		await create_timer(0.1).timeout
		_touch(5, _btn("grenade"), false)
		print("grenade thrown: ", player.grenades < g0)
		player.health = 40.0
		_touch(5, _btn("medkit"), true)
		await create_timer(0.1).timeout
		_touch(5, _btn("medkit"), false)
		print("medkit started: ", player.use_t > 0.0)
	# 暫停鈕 → 暫停選單 → 不應退出
	_touch(6, tc._pause_pos(), true)
	await create_timer(0.2).timeout
	_touch(6, tc._pause_pos(), false)
	await create_timer(0.8).timeout
	print("paused state: ", game.state, " (2=PAUSED)")
	game.set_state(game.State.PLAYING)
	await create_timer(0.3).timeout
	print("resumed state: ", game.state, " DONE")
	quit()
