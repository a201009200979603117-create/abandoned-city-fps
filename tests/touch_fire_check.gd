extends SceneTree
# 手機射擊鍵：拖曳轉視角、奔跑中射擊
#   AC_SAVE=chk godot --headless --path . -s tests/touch_fire_check.gd

var tc: Control = null


func _touch(idx: int, pos: Vector2, pressed: bool) -> void:
	# 直接呼叫處理函式（無頭模式下注入事件會被視窗縮放轉換座標而點不到按鈕）
	if pressed:
		tc._press(idx, pos)
	else:
		tc._release(idx)


func _drag(idx: int, pos: Vector2, rel: Vector2) -> void:
	tc._drag(idx, pos, rel)


func _btn(id: String) -> Vector2:
	for b in tc.BUTTONS:
		if b["id"] == id:
			return tc._button_pos(b)
	return Vector2.ZERO


func _init() -> void:
	await process_frame
	root.get_node("Save").touch_mode = true
	var game := root.get_node("Game")
	change_scene_to_file("res://main.tscn")
	await create_timer(1.0).timeout
	game.begin_run("zombie", 1)
	await create_timer(2.0).timeout
	var main := root.get_node("Main")
	main.get_node("UI")._pick_skill(0)
	await create_timer(0.5).timeout
	for c in main.get_node("UI").get_children():
		if c.get_script() != null and str(c.get_script().resource_path).ends_with("touch_controls.gd"):
			tc = c
	var player := main.get_node("Player")
	var weapon := player.get_node("Head/Camera3D/Weapon")
	print("state=", game.state, " fire_pos=", _btn("fire"), " tc.size=", tc.size, " armed=", weapon.armed)

	# 1) 按住射擊鍵 + 拖曳 → 要同時開火並轉視角（且手指不能被當成「轉視角手指」）
	var yaw0: float = player.rotation.y
	var ammo0: int = weapon.current_ammo
	_touch(1, _btn("fire"), true)
	await create_timer(0.2).timeout
	print("fire held: finger_button=", tc.finger_button, " touch_fire=", weapon.touch_fire, " look_finger=", tc.look_finger)
	_drag(1, _btn("fire") + Vector2(-90, 0), Vector2(-90, 0))
	await create_timer(0.3).timeout
	_touch(1, _btn("fire") + Vector2(-90, 0), false)
	print("RESULT fire-drag: yaw changed=", absf(player.rotation.y - yaw0) > 0.01, " fired=", weapon.current_ammo < ammo0, " (", ammo0, "->", weapon.current_ammo, ")")

	# 2) 奔跑中射擊：強制奔跑狀態後按射擊
	await create_timer(0.5).timeout
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await create_timer(0.8).timeout
	var ammo1: int = weapon.current_ammo
	_touch(2, _btn("fire"), true)
	await create_timer(0.5).timeout
	_touch(2, _btn("fire"), false)
	print("RESULT sprint-fire: sprinting=", player.is_sprinting, " fired=", weapon.current_ammo < ammo1, " (", ammo1, "->", weapon.current_ammo, ")")
	# 3) 奔跑中按開鏡：應停止奔跑並進入開鏡
	weapon.touch_zoom = true
	await create_timer(0.6).timeout
	print("RESULT sprint-then-ads: sprinting=", player.is_sprinting, " ads_factor=", snappedf(player.ads_factor, 0.01))
	weapon.touch_zoom = false
	await create_timer(0.6).timeout
	print("RESULT ads-off: sprinting=", player.is_sprinting, " ads_factor=", snappedf(player.ads_factor, 0.01))
	Input.action_release("move_forward")
	Input.action_release("sprint")
	quit()
