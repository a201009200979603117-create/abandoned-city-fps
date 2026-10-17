extends SceneTree
# 宣傳片導演腳本：以遊戲本身的場景自動拍攝（Godot Movie Maker）
#   AC_SAVE=<獨立存檔> godot --path . --write-movie out.avi --fixed-fps 30 --resolution 1920x1080 -s tests/trailer.gd
# 注意：Godot 的錄影解析度取自專案的 viewport 基準大小。正式 1080p 拍攝前，在專案根目錄建立 override.cfg：
#   [display]
#   window/size/viewport_width=1920
#   window/size/viewport_height=1080
# 拍完請刪除 override.cfg。
# 預覽（低解析度、較快）：加上 --resolution 960x540；只拍單一鏡頭：環境變數 T_ONLY=title|flyover|combat|boss|weather|br|ui|cta

# 注意：腳本載入時自動載入單例尚未就緒，因此資源一律在執行期用 load() 取得
var CoverArt: GDScript
var EquipDB: GDScript
var ENEMY: PackedScene
const GOLD := Color(0.98, 0.84, 0.55)

var game: Node
var save: Node
var sfx: Node
var main: Node3D
var player: CharacterBody3D
var hud: Node
var cam: Camera3D = null
var look_pos: Vector3 = Vector3.ZERO
var combat_on: bool = false
var invuln: bool = true

# 仿真人操作狀態
var hum_t: float = 0.0
var held: Dictionary = {}
var ads_on: bool = false
var handheld: bool = true
var target_group: String = "enemies"
var cur_target: Node3D = null
var react: float = 0.0
var burst_left: int = 3
var burst_pause: float = 0.0
var move_mode: String = "still"
var move_t: float = 0.0
var base_yaw: float = 0.0
var steer_mode: String = ""
var steer_pos: Vector3 = Vector3.ZERO
var focus: Node3D = null   # 優先瞄準的目標（Boss）
var zspeed: float = 0.6   # 拍攝用：殭屍稍慢，玩家才有餘裕走位與瞄準

# 疊加層（跨場景重新載入仍然存在）
var overlay: CanvasLayer
var fade: ColorRect
var cover: Control
var caption: Label
var cap_bg: ColorRect
var title_box: VBoxContainer
var cta_box: VBoxContainer
var music: AudioStreamPlayer


func _init() -> void:
	await process_frame
	game = root.get_node("Game")
	save = root.get_node("Save")
	sfx = root.get_node("Sfx")
	CoverArt = load("res://ui/cover_art.gd")
	EquipDB = load("res://scripts/data/equip_db.gd")
	ENEMY = load("res://scenes/enemies/Enemy.tscn")
	_prepare_profile()
	# 以實際 1920×1080 解析度錄製：關閉內容縮放，改用縮放係數讓 UI 與 1152×648 版面一致
	game.keep_window_scale = true
	# （錄影解析度取自專案設定的視窗基準大小：拍攝前需有 override.cfg 把 viewport 設為 1920×1080，見檔案頂端說明）
	root.content_scale_factor = 1920.0 / 1152.0
	_build_overlay()
	change_scene_to_file("res://main.tscn")
	await _wait(1.0)
	var only := OS.get_environment("T_ONLY")
	var shots := ["title", "flyover", "combat", "boss", "weather", "br", "ui", "cta"]
	for s in shots:
		if only != "" and not only.split(",").has(s):
			continue
		print("[trailer] shot ", s)
		await call("_shot_" + s)
	await _fade_to(1.0, 0.6)
	await _wait(0.3)
	print("[trailer] done")
	quit()


# ---------- 基本工具 ----------

func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _fade_to(a: float, dur: float) -> void:
	if a == 0.0:
		print("[trailer] fade_in_frame ", Engine.get_frames_drawn())
	var tw := fade.create_tween()
	tw.tween_property(fade, "color:a", a, dur)
	await tw.finished


func _prepare_profile() -> void:
	# 讓大廳 / 成就 / 配件等畫面看起來內容豐富
	save.quality = 2
	save.motion_blur = 0.3
	save.volume = 1.0
	save.music_volume = 0.9
	save.touch_mode = false
	save.coins = 1280
	save.xp = 11200
	save.cleared_level = 7
	save.level_best = {"1": 3250, "2": 3330, "3": 4720, "4": 5210, "5": 5860, "6": 6420, "7": 7110}
	save.br_games = 24
	save.br_wins = 6
	save.br_best_place = 1
	save.br_kills = 71
	save.br_best_points = 2300
	save.total_kills = 640
	save.selected_weapon = "rifle"
	save.selected_skin = "neon"
	save.owned_skins = ["default", "desert", "forest", "ocean", "crimson", "neon", "gold"]
	save.attachments = {"rifle": {"grip": 2, "mag": 3, "muzzle": 1, "scope": 2}}
	save.owned_equip = []
	save.equipped = {}
	for slot in EquipDB.SLOTS:
		var id: String = EquipDB.item_id(slot, 2 + (hash(slot) % 3))
		save.owned_equip.append(id)
		save.equipped[slot] = id
	save.stats = {"kills_total": 640, "headshots": 212, "boss_kills": 4, "waves": 61, "zombie_wins": 7, "br_wins": 6, "br_kills": 71, "br_top3": 11, "missions_done": 12, "explosive_kills": 23, "player_level": 15, "skins_owned": 7}
	save.achievements = {"first_blood": 1, "hunter_100": 1, "head_50": 1, "boss_1": 1, "clear_1": 1, "br_win_1": 1, "mission_10": 1, "grenade_20": 1, "wave_50": 1}
	save.missions = {}
	save.ensure_missions()
	var list: Array = save.missions["list"]
	list[0]["progress"] = int(list[0]["target"])
	list[1]["progress"] = maxi(int(list[1]["target"]) / 2, 1)
	list[2]["progress"] = int(list[2]["target"])
	list[2]["claimed"] = true
	game.audio_unlocked = true


func _build_overlay() -> void:
	overlay = CanvasLayer.new()
	overlay.layer = 100
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(overlay)

	cover = CoverArt.new()
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.visible = false
	overlay.add_child(cover)

	title_box = VBoxContainer.new()
	title_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_box.alignment = BoxContainer.ALIGNMENT_CENTER
	title_box.offset_right = -330.0   # 往左偏移，避開封面右側的月亮
	title_box.visible = false
	overlay.add_child(title_box)
	var tag := _label("SURVIVE　·　FIGHT　·　EVOLVE", 26, Color(0.95, 0.62, 0.5))
	title_box.add_child(tag)
	var main_title := _label("廢棄城市", 150, Color(0.86, 0.78, 0.64))
	main_title.add_theme_constant_override("outline_size", 22)
	main_title.add_theme_color_override("font_outline_color", Color(0.45, 0.04, 0.02))
	title_box.add_child(main_title)
	title_box.add_child(_label("ABANDONED CITY　FPS", 38, Color(0.98, 0.52, 0.36)))

	cta_box = VBoxContainer.new()
	cta_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cta_box.alignment = BoxContainer.ALIGNMENT_CENTER
	
	cta_box.visible = false
	overlay.add_child(cta_box)
	cta_box.add_theme_constant_override("separation", 10)
	cta_box.add_child(_label("廢棄城市", 92, Color(0.86, 0.78, 0.64)))
	cta_box.add_child(_label("免費下載　Windows　/　Android", 42, GOLD))
	# QR Code（由外部產生的圖片；T_QR 可指定路徑）
	var qr_path := OS.get_environment("T_QR")
	if qr_path == "":
		qr_path = OS.get_environment("TEMP") + "/trailer/qr.png"
	var qr_img := Image.load_from_file(qr_path)
	if qr_img != null:
		var holder := CenterContainer.new()
		var rect := TextureRect.new()
		rect.texture = ImageTexture.create_from_image(qr_img)
		rect.custom_minimum_size = Vector2(236.0, 236.0)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		holder.add_child(rect)
		cta_box.add_child(holder)
	cta_box.add_child(_label("掃描 QR Code 直接前往下載頁", 26, Color(0.9, 0.92, 0.98)))
	cta_box.add_child(_label("https://zfy-0920.itch.io/abandoned-city-fps", 30, Color(0.85, 0.88, 0.95)))

	cap_bg = ColorRect.new()
	cap_bg.color = Color(0, 0, 0, 0.5)
	cap_bg.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	cap_bg.offset_top = -205
	cap_bg.offset_bottom = -55
	cap_bg.modulate.a = 0.0
	cap_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(cap_bg)
	caption = _label("", 52, Color.WHITE)
	caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	caption.offset_top = -190
	caption.offset_bottom = -70
	caption.modulate.a = 0.0
	overlay.add_child(caption)

	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 1.0)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(fade)

	# 背景音樂（沿用大廳曲）；遊戲內的音效由引擎原樣錄製
	if OS.get_environment("T_MUSIC") != "1":
		return   # 預設不錄音樂：各鏡頭分開錄製，背景音樂在後製時統一混入
	music = AudioStreamPlayer.new()
	music.bus = "Music"
	music.process_mode = Node.PROCESS_MODE_ALWAYS
	music.stream = sfx.music_stream
	music.volume_db = -9.0
	root.add_child(music)
	music.play()


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.92))
	l.add_theme_constant_override("outline_size", maxi(size / 7, 3))
	return l


# 字幕：淡入、停留、淡出
func _caption(text: String, hold: float = 3.0) -> void:
	if OS.get_environment("T_NOCAP") == "1":
		return   # 拍商店截圖用：不顯示字幕
	caption.text = text
	var tw := caption.create_tween()
	tw.tween_property(caption, "modulate:a", 1.0, 0.45)
	tw.parallel().tween_property(cap_bg, "modulate:a", 1.0, 0.45)
	tw.tween_interval(hold)
	tw.tween_property(caption, "modulate:a", 0.0, 0.5)
	tw.parallel().tween_property(cap_bg, "modulate:a", 0.0, 0.5)


# ---------- 每幀：音樂控管、鏡頭看向目標、仿真人操作 ----------

func _process(delta: float) -> bool:
	if sfx == null or fade == null:
		return false
	hum_t += delta
	if sfx.music_player != null and sfx.music_player.playing:
		sfx.music_player.stop()   # 預告片自己播放音樂，避免與大廳音樂重疊
	if cam != null and is_instance_valid(cam):
		cam.look_at(look_pos, Vector3.UP)
		# 空拍的手持感：微幅抖動與側傾
		cam.h_offset = sin(hum_t * 2.3) * 0.05 + sin(hum_t * 5.1) * 0.015
		cam.v_offset = sin(hum_t * 1.9 + 1.0) * 0.05 + sin(hum_t * 4.3) * 0.015
		cam.rotate_object_local(Vector3.FORWARD, sin(hum_t * 0.9) * 0.012)
	if player != null and is_instance_valid(player):
		if invuln:
			player.health = player.max_health
		if combat_on:
			_human_combat(delta)
		elif steer_mode != "":
			_steer(delta)
		if handheld and cam == null:
			# 手持晃動：緩慢的側傾與呼吸起伏
			var pc := player.get_node("Head/Camera3D") as Camera3D
			pc.rotation.z = float(player.sway_roll) + sin(hum_t * 1.1) * 0.011 + sin(hum_t * 2.9) * 0.005
	return false


# 以輸入事件觸發動作（比 Input.action_press 更貼近真實按鍵，just_pressed 判定才會生效）
func _tap(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await create_timer(0.1).timeout
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)


func _hold(action: String, on: bool) -> void:
	if bool(held.get(action, false)) == on:
		return
	held[action] = on
	if on:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _release_all() -> void:
	for a in held.keys():
		if bool(held[a]):
			Input.action_release(a)
	held.clear()
	_set_ads(false)


# 模擬滑鼠右鍵（開鏡）：武器腳本讀取的是真實的滑鼠狀態
func _set_ads(on: bool) -> void:
	if on == ads_on:
		return
	ads_on = on
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = on
	ev.position = Vector2(960.0, 540.0)
	ev.button_mask = MOUSE_BUTTON_MASK_RIGHT if on else 0
	Input.parse_input_event(ev)


func _nearest(group: String, max_d: float) -> Node3D:
	var best: Node3D = null
	var best_d := max_d
	for e in get_nodes_in_group(group):
		var n := e as Node3D
		if n == null or n.get("is_dead") == true or n.get("dropping") == true:
			continue
		var d := n.global_position.distance_to(player.global_position)
		if d < best_d:
			best_d = d
			best = n
	return best


func _clear_dir(local: Vector3, dist: float = 3.2) -> bool:
	var from := player.global_position + Vector3(0.0, 1.0, 0.0)
	var to := from + player.global_transform.basis * local * dist
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [player.get_rid()]
	return player.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _aim_at(world: Vector3, delta: float, rate: float) -> float:
	var camera := player.get_node("Head/Camera3D") as Camera3D
	var dir := world - camera.global_position
	var yaw := atan2(-dir.x, -dir.z)
	var pitch := asin(clampf(dir.y / maxf(dir.length(), 0.01), -1.0, 1.0))
	var k := 1.0 - exp(-delta * rate)
	player.rotation.y = lerp_angle(player.rotation.y, yaw, k)
	var head := player.get_node("Head") as Node3D
	head.rotation.x = lerpf(head.rotation.x, pitch, k)
	var fwd := -camera.global_transform.basis.z
	return fwd.angle_to(dir.normalized())


# 像真人一樣作戰：走位（左右橫移、貼近時後退、遠距離蹲下）、遠距離開鏡、鎖定前有反應時間、點放連射
func _human_combat(delta: float) -> void:
	var weapon := player.get_node_or_null("Head/Camera3D/Weapon")
	if weapon == null:
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	weapon.reserve_ammo = 999
	weapon.spread_deg = 0.2
	var tgt := _nearest(target_group, 55.0)
	if focus != null and is_instance_valid(focus) and focus.get("is_dead") != true:
		if tgt == null or tgt.global_position.distance_to(player.global_position) > 7.0:
			tgt = focus
	if tgt != cur_target:
		cur_target = tgt
		react = randf_range(0.15, 0.3) if tgt != null else 0.0
	react = maxf(react - delta, 0.0)
	if tgt == null:
		_hold("move_back", false)
		_hold("crouch", false)
		_set_ads(false)
		# 沒有目標：邊走邊左右張望
		_hold("move_forward", false)
		var wy: float = base_yaw + sin(hum_t * 0.8) * 0.2
		player.rotation.y = lerp_angle(player.rotation.y, wy, 1.0 - exp(-delta * 2.0))
		return
	var d := tgt.global_position.distance_to(player.global_position)
	# --- 走位 ---
	move_t -= delta
	if move_t <= 0.0:
		move_t = randf_range(1.1, 2.3)
		var opts: Array = ["left", "right", "left", "right", "crouch", "still"] if d > 12.0 else ["left", "right", "back"]
		move_mode = opts.pick_random()
	var eff := move_mode
	if d < 6.5:
		eff = "back"
	# 不往被擋住的方向走（避免貼進車體 / 牆面造成鏡頭被遮住）
	var dirs := {"left": Vector3(-1, 0, 0), "right": Vector3(1, 0, 0), "back": Vector3(0, 0, 1)}
	if dirs.has(eff) and not _clear_dir(dirs[eff]):
		eff = "still"
		for alt in ["right", "left", "back"]:
			if _clear_dir(dirs[alt]):
				eff = alt
				break
		move_mode = eff
	_hold("move_left", eff == "left")
	_hold("move_right", eff == "right")
	_hold("move_back", eff == "back")
	_hold("crouch", eff == "crouch" and d > 9.0)
	# --- 開鏡（遠距離；貼身就放開） ---
	if d > 11.0 and eff != "back":
		_set_ads(true)
	elif d < 8.0 or eff == "back":
		_set_ads(false)
	# --- 瞄準：含手部微顫，鎖定前轉動較慢 ---
	var aim := tgt.global_position + Vector3(0.0, 1.55 * tgt.scale.y, 0.0)
	aim += Vector3(sin(hum_t * 2.1) * 0.07, sin(hum_t * 1.7) * 0.05, cos(hum_t * 1.9) * 0.04)
	var rate := 1.6 if react > 0.0 else (9.0 if ads_on else 11.0)
	var ang := _aim_at(aim, delta, rate)
	# --- 點放射擊 ---
	burst_pause -= delta
	var thresh := 0.055 if ads_on else 0.09
	if react <= 0.0 and ang < thresh and burst_pause <= 0.0 and weapon.fire_timer <= 0.0 and weapon.reload_left <= 0.0:
		weapon.shoot()
		burst_left -= 1
		if burst_left <= 0:
			burst_left = randi_range(4, 8)
			burst_pause = randf_range(0.12, 0.3)


# 移動目標導引：跳傘時飛向目標、落地後跑向目標
func _steer(delta: float) -> void:
	var to := steer_pos - player.global_position
	to.y = 0.0
	var dist := to.length()
	var yaw := atan2(-to.x, -to.z)
	var head := player.get_node("Head") as Node3D
	if steer_mode == "dive":
		player.rotation.y = lerp_angle(player.rotation.y, yaw + sin(hum_t * 0.9) * 0.08, 1.0 - exp(-delta * 3.0))
		var want_pitch := -0.2 if bool(player.chute_open) else -0.85
		head.rotation.x = lerpf(head.rotation.x, want_pitch + sin(hum_t * 1.3) * 0.03, 1.0 - exp(-delta * 2.5))
		_hold("move_forward", dist > 5.0)
	elif steer_mode == "run":
		player.rotation.y = lerp_angle(player.rotation.y, yaw, 1.0 - exp(-delta * 5.0))
		head.rotation.x = lerpf(head.rotation.x, 0.05 + sin(hum_t * 1.4) * 0.03, 1.0 - exp(-delta * 4.0))
		_hold("move_forward", dist > 1.4)
		_hold("sprint", dist > 5.0)


# ---------- 載入場景 ----------

func _begin(mode: String, level: int) -> void:
	cam = null
	combat_on = false
	steer_mode = ""
	_release_all()
	game.begin_run(mode, level)
	await _wait(0.4)
	var guard := 0
	while (not game.level_ready or game.state == game.State.MENU) and guard < 900:
		await process_frame
		guard += 1
	await _wait(0.6)
	main = root.get_node("Main")
	player = main.get_node("Player")
	hud = main.get_node("UI")
	if hud.get("toast_box") != null:
		hud.toast_box.visible = false   # 預告片不顯示成就 / 升級通知
	if mode == "zombie":
		if game.state == game.State.SKILL:
			hud._pick_skill(0)
			if hud.banner_tween:
				hud.banner_tween.kill()
			hud.banner.modulate.a = 0.0
		var sp := get_first_node_in_group("enemy_spawner")
		if sp != null:
			sp.set_physics_process(false)
		for e in get_nodes_in_group("enemies"):
			e.queue_free()


# 拍攝用調色：提高亮度與環境光，讓夜景在影片中看得清楚
func _grade(brightness: float, ambient_mul: float) -> void:
	var we := main.get_node_or_null("World/WorldEnvironment") as WorldEnvironment
	if we == null or we.environment == null:
		return
	we.environment.adjustment_brightness = brightness
	we.environment.ambient_light_energy *= ambient_mul


func _free_cam(pos: Vector3, fov: float = 68.0) -> void:
	cam = Camera3D.new()
	cam.fov = fov
	cam.far = 260.0
	main.add_child(cam)
	cam.global_position = pos
	cam.current = true


func _player_cam() -> void:
	if cam != null and is_instance_valid(cam):
		cam.queue_free()
	cam = null
	(player.get_node("Head/Camera3D") as Camera3D).current = true


func _spawn(type: int, pos: Vector3, wave: int = 4) -> Node3D:
	var e := ENEMY.instantiate()
	e.setup(type, wave)
	e.move_speed *= zspeed
	main.add_child(e)
	e.global_position = pos
	return e


# 在玩家前方的扇形內生成敵人
func _spawn_front(type: int, dist: float, side: float) -> Node3D:
	var fwd := -player.global_transform.basis.z
	var right := player.global_transform.basis.x
	return _spawn(type, player.global_position + fwd * dist + right * side)


func _cut_in() -> void:
	await _fade_to(0.0, 0.5)


func _cut_out() -> void:
	await _fade_to(1.0, 0.5)


# ---------- 鏡頭 ----------

func _shot_title() -> void:
	cover.visible = true
	title_box.visible = true
	title_box.modulate.a = 0.0
	await _fade_to(0.0, 0.8)
	var tw := title_box.create_tween()
	tw.tween_property(title_box, "modulate:a", 1.0, 1.2)
	await _wait(4.4)
	await _cut_out()
	title_box.visible = false
	cover.visible = false


func _shot_flyover() -> void:
	await _begin("zombie", 5)
	hud.visible = false
	_free_cam(Vector3(2.5, 4.5, 80.0))
	look_pos = Vector3(0.0, 3.0, 40.0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(cam, "global_position", Vector3(-1.5, 6.5, -20.0), 12.0).set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "look_pos", Vector3(0.0, 4.0, -60.0), 12.0).set_trans(Tween.TRANS_SINE)
	await _cut_in()
	_caption("末日降臨　廢棄城市", 8.0)
	await _wait(11.3)
	await _cut_out()


# 開場跑一小段路（衝刺→慢走），再進入戰鬥
func _run_in(z: float, secs: float) -> void:
	player.global_position = Vector3(1.5, 0.1, z)
	player.rotation.y = 0.0
	base_yaw = 0.0
	player.get_node("Head").rotation.x = 0.0
	handheld = true
	_player_cam()


func _walk_forward(secs: float, sprint: bool) -> void:
	_hold("move_forward", true)
	_hold("sprint", sprint)
	var t := 0.0
	while t < secs:
		var dt := 1.0 / 30.0
		player.rotation.y = lerp_angle(player.rotation.y, base_yaw + sin(hum_t * 0.8) * 0.22, 0.05)
		(player.get_node("Head") as Node3D).rotation.x = sin(hum_t * 1.1) * 0.03
		await process_frame
		t += dt
	_hold("move_forward", false)
	_hold("sprint", false)


func _shot_combat() -> void:
	if main == null or game.level != 5 or not is_instance_valid(player):
		await _begin("zombie", 5)
	target_group = "enemies"
	hud.visible = true
	_run_in(34.0, 0.0)
	# 路中央先放一個油桶，戰鬥中被引爆
	var barrel := StaticBody3D.new()
	barrel.set_script(load("res://scripts/systems/explosive_barrel.gd"))
	main.add_child(barrel)
	barrel.global_position = Vector3(2.5, 0.45, 6.0)
	_spawn(0, Vector3(-2.0, 0.1, -4.0))
	_spawn(0, Vector3(3.5, 0.1, -8.0))
	await _cut_in()
	_caption("爆頭、技能、爆炸　撐過一波又一波", 9.0)
	await _walk_forward(1.5, true)
	combat_on = true
	for i in 5:
		_spawn_front(0, 13.0 + float(i) * 1.6, float(i - 2) * 2.4)
		await _wait(0.5)
	_spawn_front(1, 17.0, -3.0)
	await _wait(3.4)
	var skills := main.get_node_or_null("Skills")
	if skills != null:
		game.skill_levels["shockwave"] = 2
		skills.cast("shockwave")
	for i in 4:
		_spawn_front(1 if i == 1 else 0, 13.0 + float(i) * 1.5, float(i - 1) * 2.8)
		await _wait(0.4)
	await _wait(3.4)
	combat_on = false
	_release_all()
	await _cut_out()


func _shot_boss() -> void:
	if main == null or not is_instance_valid(player) or game.level != 5:
		await _begin("zombie", 5)
	target_group = "enemies"
	hud.visible = true
	for e in get_nodes_in_group("enemies"):
		e.queue_free()
	_run_in(24.0, 0.0)
	var boss := _spawn(3, player.global_position + Vector3(0.0, 0.0, -17.0), 6)
	focus = boss
	boss.boss_name = "碎骨領主"
	boss.max_health = 2600.0
	boss.health = 2600.0
	boss.slam_cd = 2.0
	boss.charge_cd = 4.5
	await _cut_in()
	combat_on = true
	_caption("Boss 巨獸　吐酸殭屍　膨脹者", 9.0)
	await _wait(3.4)
	_spawn_front(4, 18.0, -5.0)
	_spawn_front(5, 14.0, 5.0)
	await _wait(9.5)
	combat_on = false
	focus = null
	_release_all()
	await _cut_out()
	if is_instance_valid(boss):
		boss.queue_free()


func _shot_weather() -> void:
	await _begin("zombie", 9)
	target_group = "enemies"
	hud.visible = true
	for z in get_nodes_in_group("toxic_zones"):
		z.queue_free()
	_grade(1.35, 2.3)
	_run_in(20.0, 0.0)
	# 讓第一道閃電盡快出現
	var wx = null
	for c in main.get_node("LevelBuilder").get_children():
		if c.get("lightning_t") != null:
			wx = c
	if wx != null:
		wx.lightning_t = 1.0
	await _cut_in()
	_caption("夜晚　暴風雨　濃霧　每一關都不同", 9.0)
	await _walk_forward(1.8, false)
	combat_on = true
	for i in 8:
		_spawn_front(1 if i == 1 else 0, 13.0 + float(i) * 1.5, float(i % 5 - 2) * 2.0)
		await _wait(0.5)
	await _wait(7.5)
	combat_on = false
	_release_all()
	await _cut_out()


func _place_bot(mgr: Node, bot: Node3D, pos: Vector3, gun: String) -> void:
	bot.set("dropping", false)
	var canopy = bot.get("canopy")
	if canopy != null and is_instance_valid(canopy):
		canopy.queue_free()
		bot.set("canopy", null)
	bot.global_position = Vector3(pos.x, 0.1, pos.z)
	bot.velocity = Vector3.ZERO
	bot.give_weapon(gun, 30, 90)


func _shot_br() -> void:
	game.force_weather = "clear"
	game.force_tod = "dusk"
	await _begin("br", 1)
	game.force_weather = ""
	game.force_tod = ""
	target_group = "br_bots"
	hud.visible = true
	invuln = true
	var mgr := main.get_node("BR")
	var guard := 0
	while not mgr.started and guard < 600:
		await process_frame
		guard += 1
	await _wait(0.3)
	if mgr.zone_mesh != null:
		mgr.zone_mesh.visible = false   # 跳傘時鏡頭在縮圈柱體內，隱藏避免整片藍色
	# 預定落點：放一把步槍，附近其他槍清掉，確保撿到的是它
	var spot := Vector3(0.6, 0.05, 22.0)   # 中央大道（路寬 12 公尺，兩側是建築），沿著街道向 -z 作戰
	for g in get_nodes_in_group("gun_pickups"):
		if (g as Node3D).global_position.distance_to(spot) < 16.0:
			g.queue_free()
	for g in get_nodes_in_group("item_pickups"):
		if (g as Node3D).global_position.distance_to(spot) < 16.0:
			g.queue_free()
	var rifle_pickup: Node3D = mgr.spawn_gun("rifle", spot)
	# 空投箱落在身後的路上
	mgr._spawn_supply()
	var crate: Node3D = mgr.supply_drops[0]
	crate.global_position = Vector3(-2.0, 80.0, spot.z + 15.0)
	# 從約 95 公尺外的高空起跳，操控飛向落點
	var from := Vector3(spot.x, 0.0, spot.z) + Vector3(0.7, 0.0, 0.7).normalized() * 70.0
	from.x = clampf(from.x, -92.0, 92.0)
	from.z = clampf(from.z, -92.0, 92.0)
	player.global_position = Vector3(from.x, 130.0, from.z)
	player.rotation.y = atan2(-(spot.x - from.x), -(spot.z - from.z))
	player.get_node("Head").rotation.x = -0.85
	steer_pos = spot
	steer_mode = "dive"
	await _cut_in()
	_caption("12 人大逃殺　跳傘・搶槍・縮圈・空投", 10.0)
	# 自由落體 → 開傘；開傘後再過一會兒剪接到近地面
	guard = 0
	while not player.chute_open and guard < 400:
		await _wait(0.1)
		guard += 1
	await _wait(1.6)
	await _fade_to(1.0, 0.25)
	player.global_position = Vector3(spot.x + 3.0, 16.0, spot.z + 4.0)
	await _fade_to(0.0, 0.25)
	guard = 0
	while player.skydiving and guard < 200:
		await _wait(0.1)
		guard += 1
	if mgr.zone_mesh != null:
		mgr._update_zone_mesh()
	# 落地後奔向步槍並撿起
	steer_mode = "run"
	steer_pos = spot
	guard = 0
	while player.global_position.distance_to(spot) > 1.6 and guard < 150:
		await _wait(0.1)
		guard += 1
	steer_mode = ""
	_hold("move_forward", false)
	_hold("sprint", false)
	await _wait(0.25)
	var weapon_node := player.get_node("Head/Camera3D/Weapon")
	for k in 4:
		if weapon_node.armed:
			break
		_tap("interact")
		await _wait(0.5)
		await _wait(0.4)
	print("[trailer] pickup armed=", weapon_node.armed, " dist=", player.global_position.distance_to(spot), " guns=", get_nodes_in_group("gun_pickups").size())
	await _wait(0.4)
	# 面向前方街道；三名敵人隔著油桶出現，先丟一顆手榴彈
	player.rotation.y = 0.0   # 面向 -z 的街道
	base_yaw = 0.0
	player.get_node("Head").rotation.x = 0.1
	var fwd := -player.global_transform.basis.z
	var right := player.global_transform.basis.x
	var c := player.global_position + fwd * 12.5
	var live: Array = []
	for b in mgr.bots:
		if is_instance_valid(b) and not bool(b.get("is_dead")):
			live.append(b)
	var offs := [Vector3(-2.2, 0, 0.8), Vector3(0.4, 0, -1.2), Vector3(2.4, 0, 0.6)]
	for i in mini(3, live.size()):
		var o: Vector3 = offs[i]
		_place_bot(mgr, live[i], c + right * o.x + fwd * o.z, "smg" if i != 1 else "rifle")
	for k in 2:
		var barrel := StaticBody3D.new()
		barrel.set_script(load("res://scripts/systems/explosive_barrel.gd"))
		main.add_child(barrel)
		barrel.global_position = Vector3(c.x + right.x * (float(k) * 1.6 - 0.8), 0.45, c.z + right.z * (float(k) * 1.6 - 0.8))
	player.grenades = 3
	await _wait(0.5)
	player.throw_grenade()
	await _wait(2.4)
	# 開鏡、蹲下與敵人對槍
	combat_on = true
	if live.size() > 4:
		var far_c := player.global_position - right * 6.0 + fwd * 26.0
		_place_bot(mgr, live[3], far_c, "rifle")
		_place_bot(mgr, live[4], far_c + right * 5.0 + fwd * 3.0, "smg")
	await _wait(9.5)
	combat_on = false
	_release_all()
	# 走向空投箱開啟
	guard = 0
	while not crate.is_landed() and guard < 80:
		await _wait(0.25)
		guard += 1
	steer_mode = "run"
	steer_pos = crate.global_position
	guard = 0
	while player.global_position.distance_to(crate.global_position) > 2.6 and guard < 120:
		await _wait(0.1)
		guard += 1
	steer_mode = ""
	_hold("move_forward", false)
	_hold("sprint", false)
	_tap("interact")
	await _wait(2.4)
	await _cut_out()


func _shot_ui() -> void:
	game.return_to_lobby()
	await _wait(1.4)
	hud = root.get_node("Main/UI")
	var mu = hud.menu_ui
	cover.visible = false
	await _cut_in()
	_caption("等級・成就・每日任務・槍枝配件", 8.5)
	mu.show_page("lobby")
	await _wait(2.4)
	mu.show_page("weapons")
	await _wait(2.8)
	mu.show_page("quests")
	await _wait(2.4)
	mu.quest_tab = "ach"
	mu.show_page("quests")
	await _wait(2.6)
	await _cut_out()


func _shot_cta() -> void:
	cover.visible = true
	cta_box.visible = true
	cta_box.modulate.a = 0.0
	await _fade_to(0.0, 0.7)
	var tw := cta_box.create_tween()
	tw.tween_property(cta_box, "modulate:a", 1.0, 1.0)
	await _wait(5.8)
	await _cut_out()
	cta_box.visible = false
