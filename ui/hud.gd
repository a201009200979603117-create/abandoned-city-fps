extends CanvasLayer

const MenuUI = preload("res://ui/menu_ui.gd")
const SkillDB = preload("res://scripts/data/skill_db.gd")
const WeaponDB = preload("res://scripts/data/weapon_db.gd")
const EquipDB = preload("res://scripts/data/equip_db.gd")
const LevelDB = preload("res://scripts/data/level_db.gd")
const Minimap = preload("res://ui/minimap.gd")
const TouchControls = preload("res://ui/touch_controls.gd")
const UIUtil = preload("res://ui/ui_util.gd")
const MotionBlur = preload("res://ui/motion_blur.gd")
const DamageIndicator = preload("res://ui/damage_indicator.gd")
# HUD、開始/暫停/勝利/失敗選單。全部以程式建立，場景中只需要既有的四個 Label。

@onready var health_label: Label = $HealthLabel
@onready var ammo_label: Label = $AmmoLabel
@onready var crosshair: Label = $Crosshair
@onready var pickup_hint: Label = $PickupHint

var player: Node = null
var health_bar: ProgressBar
var wave_label: Label
var enemy_label: Label
var score_label: Label
var banner: Label
var hit_marker: Label
var damage_overlay: ColorRect
var menu_root: Control
var menu_title: Label
var menu_panel: PanelContainer
var menu_rule: ColorRect
var menu_body: Label
var button_box: Container
var menu_ui: Control
var skill_root: Control
var skill_title: Label
var skill_sub: Label
var skill_cards: HBoxContainer
var pending_options: Array = []
var skill_slots: Array = []
var skill_bar: HBoxContainer
var slot_px: float = 68.0 if Save.touch_mode else 88.0
var weapon_label: Label
var skills_node: Node = null
var hud_items: Array = []
var minimap: Control
var feed_box: VBoxContainer
var br_node: Node = null
var banner_tween: Tween
var toast_box: VBoxContainer
var dmg_indicator: Control
var shield_bar: ProgressBar
var item_label: Label
var boss_box: VBoxContainer
var boss_bar: ProgressBar
var boss_label: Label
var boss_ref: Node = null
var hit_tween: Tween
var damage_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.reset()

	player = get_tree().get_first_node_in_group("player")
	if player != null and player.has_signal("damaged"):
		player.damaged.connect(_on_player_damaged)
	dmg_indicator = DamageIndicator.new()
	add_child(dmg_indicator)
	if player != null and player.has_signal("hit_from"):
		player.hit_from.connect(dmg_indicator.add_hit)

	get_parent().add_child.call_deferred(MotionBlur.new())
	_build_hud()
	_build_menu()
	_build_skill_ui()
	_build_skill_bar()
	menu_ui = MenuUI.new()
	add_child(menu_ui)
	menu_ui.quit_requested.connect(_on_quit)
	menu_ui.closed.connect(_on_settings_closed)
	_build_br_hud()
	if Save.touch_mode:
		_touch_layout()
		var tc: Control = TouchControls.new()
		tc.hud = self
		add_child(tc)
	hud_items = [health_label, health_bar, ammo_label, crosshair, wave_label, enemy_label, score_label, weapon_label]
	if Game.is_br():
		hud_items.append(minimap)
		hud_items.append(feed_box)
		skill_bar.visible = false
	else:
		hud_items.append(skill_bar)

	Game.state_changed.connect(_on_state_changed)
	Game.wave_started.connect(_on_wave_started)
	Game.wave_cleared.connect(_on_wave_cleared)
	Game.hit_marker.connect(_on_hit_marker)
	Game.hit_detail.connect(_on_hit_detail)
	Game.skill_cast.connect(_on_skill_cast)
	Game.banner.connect(_show_banner)
	Game.kill_feed.connect(_on_kill_feed)
	Game.toast.connect(_on_toast)
	Game.boss_changed.connect(_on_boss_changed)

	var weapon_node := get_node_or_null("/root/Main/Player/Head/Camera3D/Weapon")
	if weapon_node != null:
		weapon_node.update_ammo_ui()

	if Game.skip_menu:
		Game.skip_menu = false
		_begin_run()
	else:
		_on_state_changed(Game.State.MENU)
		Game.show_lobby = false


func _notification(what: int) -> void:
	# 手機返回鍵：遊戲中暫停 / 取消暫停
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if menu_ui != null and menu_ui.visible:
			return   # 由選單自己處理
		if Game.state == Game.State.PLAYING:
			Game.set_state(Game.State.PAUSED)
		elif Game.state == Game.State.PAUSED:
			Game.set_state(Game.State.PLAYING)


func _unhandled_input(event: InputEvent) -> void:
	if Game.state == Game.State.SKILL and event is InputEventKey and event.pressed and not event.echo:
		var idx: int = [KEY_1, KEY_2, KEY_3].find(event.physical_keycode)
		if idx >= 0 and idx < pending_options.size():
			_pick_skill(idx)
		return
	if event.is_action_pressed("ui_cancel"):
		if menu_ui != null and menu_ui.visible and menu_ui.pause_mode:
			menu_ui._back()
			return
		if Game.state == Game.State.PLAYING:
			Game.set_state(Game.State.PAUSED)
		elif Game.state == Game.State.PAUSED:
			Game.set_state(Game.State.PLAYING)


var hud_acc: float = 0.0


func _process(delta: float) -> void:
	hud_acc += delta
	var tick := hud_acc >= 0.1
	if tick:
		hud_acc = 0.0
	# 血條等進度條每幀更新（便宜）；文字標籤每 0.1 秒更新一次（避免每幀配置字串）
	if boss_ref != null and is_instance_valid(boss_ref):
		boss_bar.value = float(boss_ref.get("health"))
	elif boss_box != null and boss_box.visible:
		boss_box.visible = false
	if player != null and is_instance_valid(player):
		health_bar.max_value = player.max_health
		health_bar.value = player.health
		if Game.is_br() and shield_bar != null and Game.state != Game.State.MENU:
			shield_bar.visible = float(player.get("shield")) > 0.0
			shield_bar.value = float(player.get("shield"))
			if tick and not Save.touch_mode:
				item_label.visible = true
				var use_text := ""
				if float(player.get("use_t")) > 0.0:
					use_text = "　【使用中 %.1f】" % float(player.get("use_t"))
				item_label.text = "G 手榴彈 ×%d　H 醫療包 ×%d　T 護甲板 ×%d%s" % [int(player.get("grenades")), int(player.get("medkits")), int(player.get("plates")), use_text]
	if not tick:
		if not Game.is_br():
			_update_skill_bar()   # 技能冷卻遮罩需要每幀平滑更新
		return
	if Game.is_br():
		if br_node == null:
			br_node = get_node_or_null("/root/Main/BR")
		wave_label.text = "存活 %d / %d" % [Game.br_alive, Game.BR_PLAYERS]
		if br_node != null and bool(br_node.get("started")) and br_node.diving():
			enemy_label.text = br_node.dive_text()
		elif br_node != null and bool(br_node.get("started")):
			enemy_label.text = "%s　圈外傷害 %d/秒" % [br_node.zone_text(), int(br_node.zone_dps())]
		else:
			enemy_label.text = "準備中…"
		score_label.text = "擊殺：%d
喪屍幣 +%d" % [Game.kills, Game.run_coins]
	else:
		wave_label.text = "第 %d 關　第 %d / %d 波" % [Game.level, maxi(Game.wave, 1), Game.total_waves]
		enemy_label.text = "剩餘敵人：%d" % Game.enemies_remaining
		score_label.text = "分數：%d
擊殺：%d
喪屍幣 +%d" % [Game.score, Game.kills, Game.run_coins]
		_update_skill_bar()


# ---------- 建立介面 ----------

func _style(l: Label, size: int, color: Color = Color.WHITE) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 6)


func _place(c: Control, ax: float, ay: float, l: float, t: float, r: float, b: float) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = l
	c.offset_top = t
	c.offset_right = r
	c.offset_bottom = b
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH if ax == 0.5 else Control.GROW_DIRECTION_END
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _make_label(size: int, color: Color = Color.WHITE, align: HorizontalAlignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	_style(l, size, color)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _build_hud() -> void:
	# 受傷紅色閃光（放最底層）
	damage_overlay = ColorRect.new()
	damage_overlay.color = Color(0.8, 0.0, 0.0, 0.0)
	damage_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	damage_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(damage_overlay)
	move_child(damage_overlay, 0)

	_style(health_label, 24)
	_place(health_label, 0.0, 1.0, 24.0, -84.0, 324.0, -50.0)
	health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	health_bar = ProgressBar.new()
	health_bar.show_percentage = false
	health_bar.max_value = 100.0
	health_bar.value = 100.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.62, 0.2, 0.14)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.04, 0.035, 0.03, 0.7)
	health_bar.add_theme_stylebox_override("fill", fill)
	health_bar.add_theme_stylebox_override("background", back)
	add_child(health_bar)
	_place(health_bar, 0.0, 1.0, 24.0, -44.0, 324.0, -24.0)

	# 護盾條（大逃殺）與道具數量
	shield_bar = ProgressBar.new()
	shield_bar.show_percentage = false
	shield_bar.max_value = 50.0
	shield_bar.value = 0.0
	var sfill := StyleBoxFlat.new()
	sfill.bg_color = Color(0.35, 0.65, 1.0)
	var sback := StyleBoxFlat.new()
	sback.bg_color = Color(0.0, 0.0, 0.0, 0.5)
	shield_bar.add_theme_stylebox_override("fill", sfill)
	shield_bar.add_theme_stylebox_override("background", sback)
	shield_bar.visible = false
	add_child(shield_bar)
	_place(shield_bar, 0.0, 1.0, 24.0, -52.0, 324.0, -46.0)
	item_label = _make_label(19, Color(0.9, 0.95, 0.85), HORIZONTAL_ALIGNMENT_LEFT)
	_place(item_label, 0.0, 1.0, 24.0, -118.0, 520.0, -90.0)
	item_label.visible = false

	_style(ammo_label, 34)
	_place(ammo_label, 1.0, 1.0, -324.0, -84.0, -24.0, -34.0)
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_style(crosshair, 28)
	_style(pickup_hint, 22, Color(0.85, 0.78, 0.5))

	wave_label = _make_label(30)
	_place(wave_label, 0.5, 0.0, -260.0, 16.0, 260.0, 56.0)
	enemy_label = _make_label(20, Color(0.82, 0.68, 0.62))
	_place(enemy_label, 0.5, 0.0, -300.0, 58.0, 300.0, 88.0)

	score_label = _make_label(22, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	_place(score_label, 1.0, 0.0, -324.0, 16.0, -24.0, 110.0)

	weapon_label = _make_label(20, Color(0.82, 0.76, 0.58), HORIZONTAL_ALIGNMENT_RIGHT)
	weapon_label.name = "WeaponLabel"
	weapon_label.text = ""
	_place(weapon_label, 1.0, 1.0, -424.0, -116.0, -24.0, -86.0)

	# 通知（成就 / 任務 / 升級）：由上而下堆疊，數秒後淡出
	toast_box = VBoxContainer.new()
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_box.add_theme_constant_override("separation", 6)
	add_child(toast_box)
	_place(toast_box, 0.5, 0.0, -230.0, 108.0, 230.0, 300.0)

	# Boss 血條
	boss_box = VBoxContainer.new()
	boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_box.visible = false
	add_child(boss_box)
	_place(boss_box, 0.5, 0.0, -270.0, 96.0, 270.0, 150.0)
	boss_label = Label.new()
	_style(boss_label, 22, Color(1.0, 0.45, 0.35))
	boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_box.add_child(boss_label)
	boss_bar = ProgressBar.new()
	boss_bar.show_percentage = false
	boss_bar.custom_minimum_size = Vector2(540.0, 16.0)
	var bf := StyleBoxFlat.new()
	bf.bg_color = Color(0.8, 0.12, 0.1)
	bf.set_corner_radius_all(5)
	var bb := StyleBoxFlat.new()
	bb.bg_color = Color(0.0, 0.0, 0.0, 0.7)
	bb.border_color = Color(0.6, 0.15, 0.12)
	bb.set_border_width_all(2)
	bb.set_corner_radius_all(5)
	boss_bar.add_theme_stylebox_override("fill", bf)
	boss_bar.add_theme_stylebox_override("background", bb)
	boss_box.add_child(boss_bar)

	banner = _make_label(48, Color(0.86, 0.78, 0.6))
	_place(banner, 0.5, 0.3, -400.0, -40.0, 400.0, 40.0)
	banner.modulate.a = 0.0

	hit_marker = _make_label(26, Color.WHITE)
	hit_marker.text = "X"
	_place(hit_marker, 0.5, 0.5, -20.0, -20.0, 20.0, 20.0)
	hit_marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hit_marker.modulate.a = 0.0


func _build_menu() -> void:
	menu_root = Control.new()
	menu_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(menu_root)

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.01, 0.02, 0.7)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_root.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_root.add_child(center)

	menu_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.045, 0.05, 0.94)
	sb.border_color = Color(0.78, 0.34, 0.2)
	sb.set_border_width_all(2)
	sb.border_width_top = 5
	sb.set_corner_radius_all(16)
	sb.content_margin_left = 54
	sb.content_margin_right = 54
	sb.content_margin_top = 34
	sb.content_margin_bottom = 40
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 28
	menu_panel.add_theme_stylebox_override("panel", sb)
	menu_panel.custom_minimum_size = Vector2(500.0, 0.0)
	center.add_child(menu_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	menu_panel.add_child(box)

	menu_title = Label.new()
	_style(menu_title, 54, Color(0.95, 0.82, 0.58))
	menu_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(menu_title)

	menu_rule = ColorRect.new()
	menu_rule.color = Color(0.78, 0.34, 0.2)
	menu_rule.custom_minimum_size = Vector2(0.0, 3.0)
	box.add_child(menu_rule)

	menu_body = Label.new()
	_style(menu_body, 20, Color(0.88, 0.88, 0.92))
	menu_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu_body.custom_minimum_size = Vector2(520.0, 0.0)
	box.add_child(menu_body)

	if Save.touch_mode:
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 12)
		button_box = grid
		sb.content_margin_top = 22
		sb.content_margin_bottom = 26
		box.add_theme_constant_override("separation", 10)
		menu_title.add_theme_font_size_override("font_size", 44)
	else:
		button_box = VBoxContainer.new()
		button_box.add_theme_constant_override("separation", 10)
	box.add_child(button_box)


func _set_buttons(items: Array) -> void:
	for c in button_box.get_children():
		c.queue_free()
	var gold := Color(0.82, 0.68, 0.34)
	var accents := {"繼續": gold, "下一關": gold, "再來一局": gold, "再玩一次": gold,
		"重新開始": Color(0.78, 0.34, 0.2), "離開": Color(0.5, 0.5, 0.55)}
	var guard_list: Array = []
	for i in items.size():
		var item: Array = items[i]
		if OS.has_feature("web") and item[0] == "離開":
			continue   # 網頁版無法離開，隱藏此按鈕
		var acc: Color = accents.get(item[0], Color(0.4, 0.62, 0.78))
		var b: Button = menu_ui._button(item[0], item[1], Vector2(290.0 if Save.touch_mode else 400.0, 54.0), acc, i == 0)
		b.add_theme_font_size_override("font_size", 23)
		menu_ui._hover_pop(b, 1.03)
		button_box.add_child(b)
		guard_list.append(b)
	_guard_buttons(guard_list)


# 新出現的選單按鈕短暫不接受點擊：避免觸控「按下暫停」的同一個點擊（或結算瞬間的連點）直接點到按鈕
func _guard_buttons(buttons: Array, secs: float = 0.4) -> void:
	for b in buttons:
		(b as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	await get_tree().create_timer(secs, true).timeout
	for b in buttons:
		if is_instance_valid(b):
			(b as Control).mouse_filter = Control.MOUSE_FILTER_STOP


func _animate_menu_in() -> void:
	menu_panel.pivot_offset = menu_panel.size * 0.5
	menu_panel.scale = Vector2(0.94, 0.94)
	menu_root.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(menu_root, "modulate:a", 1.0, 0.18)
	tw.tween_property(menu_panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _theme_menu(accent: Color, title_col: Color) -> void:
	var sb := menu_panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	sb.border_color = accent
	menu_panel.add_theme_stylebox_override("panel", sb)
	menu_rule.color = accent
	menu_title.add_theme_color_override("font_color", title_col)


# ---------- 狀態與事件 ----------

func _on_state_changed(s: int) -> void:
	var in_menu := s == Game.State.MENU
	var settings_open: bool = menu_ui != null and menu_ui.pause_mode
	menu_root.visible = (s == Game.State.PAUSED or s == Game.State.WON or s == Game.State.LOST) and not settings_open
	skill_root.visible = s == Game.State.SKILL
	move_child(menu_root, -1)
	move_child(skill_root, -1)
	if menu_ui != null:
		if in_menu:
			menu_ui.open_main(Game.show_lobby)
		else:
			menu_ui.visible = settings_open and s == Game.State.PAUSED
	for n in hud_items:
		(n as CanvasItem).visible = not in_menu
	if Save.touch_mode and Game.is_br() and weapon_label != null:
		weapon_label.visible = false   # 手機版由觸控武器欄顯示
	# 選技能時隱藏技能列，避免擋住卡片內容
	if skill_bar != null and not Game.is_br():
		skill_bar.visible = not in_menu and s != Game.State.SKILL

	match s:
		Game.State.PAUSED:
			menu_title.text = "暫停"
			_theme_menu(Color(0.78, 0.34, 0.2), Color(0.95, 0.82, 0.58))
			menu_body.text = ""
			_set_buttons([["繼續", _on_resume], ["設定", _on_open_settings], ["重新開始", _on_restart], ["回遊戲大廳", _on_main_menu]] + ([] if OS.has_feature("web") else [["離開", _on_quit]]))
		Game.State.WON:
			_theme_menu(Color(0.82, 0.68, 0.34), Color(1.0, 0.88, 0.5))
			if Game.is_br():
				menu_title.text = "勝利！大吉大利，今晚吃雞"
				_set_buttons([["再來一局", _on_restart], ["回遊戲大廳", _on_main_menu], ["離開", _on_quit]])
			else:
				menu_title.text = "第 %d 關完成！" % Game.level
				var items: Array = []
				if Game.level < LevelDB.count():
					items.append(["下一關", _on_next_level])
				items.append_array([["再玩一次", _on_restart], ["回遊戲大廳", _on_main_menu], ["離開", _on_quit]])
				_set_buttons(items)
			menu_body.text = _summary()
		Game.State.LOST:
			_theme_menu(Color(0.75, 0.15, 0.15), Color(0.95, 0.3, 0.25))
			menu_title.text = "你被淘汰了" if Game.is_br() else "你已陣亡"
			menu_body.text = _summary()
			_set_buttons([["重新開始", _on_restart], ["回遊戲大廳", _on_main_menu], ["離開", _on_quit]])

	if menu_root.visible:
		_animate_menu_in()
	if menu_root.visible and button_box.get_child_count() > 0:
		# 等按鈕重建完成後聚焦，方便鍵盤操作
		await get_tree().process_frame
		if button_box.get_child_count() > 0:
			(button_box.get_child(0) as Control).grab_focus()


func _summary() -> String:
	var r: Dictionary = Game.result
	if Game.is_br():
		var lines: PackedStringArray = []
		if Game.killed_by != "":
			lines.append("被 %s 淘汰" % Game.killed_by)
		lines.append("名次：第 %d 名 / %d　擊殺 %d" % [Game.placement, Game.BR_PLAYERS, Game.kills])
		lines.append("本局積分 %d　排行榜名次：第 %d 名" % [int(r.get("points", 0)), Game.last_rank])
		lines.append("喪屍幣：擊殺 +%d　名次獎勵 +%d（持有 %d）" % [Game.run_coins, int(r.get("place_coins", 0)), Save.coins])
		if Game.airdrop_item != "":
			lines.append("空投裝備：【%s】%s" % [EquipDB.tier_info(Game.airdrop_item)["name"], EquipDB.item_name(Game.airdrop_item)])
		lines.append(_xp_line())
		return "\n".join(lines)
	var record := "　★ 新紀錄！" if Game.score >= int(Save.level_best.get(str(Game.level), 0)) and Game.score > 0 else ""
	var lines2: PackedStringArray = []
	lines2.append("「%s」　撐到第 %d 波" % [Game.level_cfg["name"], maxi(Game.wave, 1)])
	lines2.append("擊殺 %d　分數 %d%s" % [Game.kills, Game.score, record])
	var bonus := int(r.get("clear_bonus", 0))
	lines2.append("本局喪屍幣 +%d%s（持有 %d）" % [Game.run_coins, "　首次通關獎勵 +%d" % bonus if bonus > 0 else "", Save.coins])
	lines2.append("關卡排行榜名次：第 %d 名" % Game.last_rank)
	if int(Game.run_stats.get("headshots", 0)) > 0:
		lines2.append("爆頭 %d 次" % int(Game.run_stats["headshots"]))
	lines2.append(_xp_line())
	return "\n".join(lines2)


func _begin_run() -> void:
	Game.set_state(Game.State.PLAYING)
	if not Game.is_br():
		_open_skill_pick(0)


func _on_start() -> void:
	_begin_run()


func _on_open_settings() -> void:
	menu_root.visible = false
	menu_ui.open_settings_from_pause()


func _on_settings_closed() -> void:
	menu_root.visible = Game.state == Game.State.PAUSED


func _on_main_menu() -> void:
	Game.return_to_lobby()


func _on_next_level() -> void:
	Game.begin_run("zombie", Game.level + 1)


func _on_resume() -> void:
	Game.set_state(Game.State.PLAYING)


func _on_restart() -> void:
	Game.restart_run()


func _on_quit() -> void:
	Save.save()
	get_tree().quit()


func _show_banner(text: String) -> void:
	banner.text = text
	if banner_tween:
		banner_tween.kill()
	banner.modulate.a = 1.0
	banner_tween = create_tween()
	banner_tween.tween_interval(1.6)
	banner_tween.tween_property(banner, "modulate:a", 0.0, 0.8)


func _on_wave_started(w: int) -> void:
	if w >= Game.total_waves:
		_show_banner("最終波！")
	else:
		_show_banner("第 %d 波" % w)


func _on_wave_cleared(w: int) -> void:
	if w < Game.total_waves:
		_show_banner("第 %d 波完成，補給已投放" % w)
		await get_tree().create_timer(1.4).timeout
		if is_inside_tree() and Game.state == Game.State.PLAYING:
			_open_skill_pick(w)


func _on_skill_cast(id: String, evolved: bool) -> void:
	var col: Color = SkillDB.SKILLS[id]["color"]
	if damage_tween:
		damage_tween.kill()
	damage_overlay.color = Color(col.r, col.g, col.b, 0.28)
	damage_tween = create_tween()
	damage_tween.tween_property(damage_overlay, "color:a", 0.0, 0.35)
	_show_banner(SkillDB.display_name(id, evolved))


func _on_boss_changed(boss: Node) -> void:
	boss_ref = boss
	if boss_box == null:
		return
	boss_box.visible = boss != null
	if boss != null:
		boss_label.text = "Boss　" + str(boss.get("boss_name"))
		boss_bar.max_value = float(boss.get("max_health"))


func _on_toast(title: String, text: String, color: Color) -> void:
	if toast_box == null:
		return
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.04, 0.06, 0.88)
	sb.border_color = color
	sb.set_border_width_all(2)
	sb.border_width_left = 6
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	p.add_child(v)
	var t := Label.new()
	t.text = title
	_style(t, 15, color)
	v.add_child(t)
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(300.0, 0.0)
	_style(l, 19, Color.WHITE)
	v.add_child(l)
	toast_box.add_child(p)
	while toast_box.get_child_count() > 3:
		toast_box.get_child(0).queue_free()
		toast_box.remove_child(toast_box.get_child(0))
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.2)
	tw.tween_interval(3.4)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)


func _xp_line() -> String:
	var r: Dictionary = Game.result
	var a := int(r.get("level_after", 1))
	var b := int(r.get("level_before", 1))
	var s := "經驗 +%d　Lv.%d" % [int(r.get("xp", 0)), a]
	if a > b:
		s += "（升級！Lv.%d → Lv.%d，獎勵 +%d 喪屍幣）" % [b, a, int(r.get("level_coins", 0))]
	return s


func _on_hit_marker(killed: bool) -> void:
	if hit_tween:
		hit_tween.kill()
	hit_marker.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2) if killed else Color.WHITE)
	hit_marker.modulate.a = 1.0
	hit_tween = create_tween()
	hit_tween.tween_property(hit_marker, "modulate:a", 0.0, 0.15)


# 命中提示依部位變色：爆頭金色、擊殺紅色，並有放大彈跳
func _on_hit_detail(zone: String, killed: bool, _dmg: float, _pos: Vector3) -> void:
	var col := Color.WHITE
	if zone == "head":
		col = Color(1.0, 0.8, 0.2)
	if killed:
		col = Color(1.0, 0.2, 0.2)
	hit_marker.add_theme_color_override("font_color", col)
	hit_marker.pivot_offset = hit_marker.size * 0.5
	hit_marker.scale = Vector2.ONE * (1.8 if (zone == "head" or killed) else 1.25)
	create_tween().tween_property(hit_marker, "scale", Vector2.ONE, 0.12)


func _on_player_damaged(_amount: float) -> void:
	if damage_tween:
		damage_tween.kill()
	damage_overlay.color.a = 0.4
	damage_tween = create_tween()
	damage_tween.tween_property(damage_overlay, "color:a", 0.0, 0.4)


# ---------- 技能選擇 ----------

func _build_skill_ui() -> void:
	skill_root = Control.new()
	skill_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	skill_root.visible = false
	add_child(skill_root)

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.01, 0.03, 0.82)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	skill_root.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	skill_root.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	skill_title = Label.new()
	_style(skill_title, 52, Color(0.98, 0.84, 0.55))
	skill_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(skill_title)
	var rule := ColorRect.new()
	rule.color = Color(0.78, 0.34, 0.2)
	rule.custom_minimum_size = Vector2(260.0, 3.0)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(rule)
	skill_sub = Label.new()
	_style(skill_sub, 20, Color(0.8, 0.8, 0.86))
	skill_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(skill_sub)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, 10.0)
	box.add_child(gap)

	skill_cards = HBoxContainer.new()
	skill_cards.add_theme_constant_override("separation", 26)
	skill_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(skill_cards)


func _card_style(accent: Color, hover: bool, evolve: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = accent.darkened(0.78) if not hover else accent.darkened(0.62)
	sb.bg_color.a = 0.97
	sb.border_color = accent.lightened(0.25) if hover else accent.darkened(0.15)
	sb.set_border_width_all(4 if hover or evolve else 2)
	sb.border_width_top = 6
	sb.set_corner_radius_all(16)
	sb.shadow_color = Color(accent.r, accent.g, accent.b, 0.55 if hover else (0.35 if evolve else 0.0))
	sb.shadow_size = 26 if hover else 16
	return sb


func _skill_chip(text: String, color: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color.darkened(0.55)
	sb.border_color = color
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var l := Label.new()
	l.text = text
	_style(l, 16, color.lightened(0.5))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	return p


func _make_skill_card(i: int, opt: Dictionary) -> Button:
	var id: String = opt["id"]
	var info: Dictionary = SkillDB.SKILLS[id]
	var key_name: String = SkillDB.KEY_NAMES[SkillDB.ORDER.find(id)]
	var lv := Game.skill_level(id)
	var kind: String = opt["kind"]
	var accent: Color = info["color"]
	var evolve := kind == "evolve"
	if evolve:
		accent = Color(1.0, 0.82, 0.3)

	var tag := "新技能"
	var new_lv := 1
	var detail := SkillDB.level_desc(id, 1, false)
	var detail_head := "Lv1 效果"
	match kind:
		"upgrade":
			tag = "升級  Lv%d → Lv%d" % [lv, lv + 1]
			new_lv = lv + 1
			detail = SkillDB.level_desc(id, lv + 1, false)
			detail_head = "Lv%d 效果" % (lv + 1)
		"evolve":
			tag = "★ 突破 ★"
			new_lv = SkillDB.MAX_LEVEL
			detail = SkillDB.level_desc(id, lv, true)
			detail_head = "突破效果"

	var b := Button.new()
	b.custom_minimum_size = Vector2(292.0, 396.0) if Save.touch_mode else Vector2(300.0, 440.0)
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_stylebox_override("normal", _card_style(accent, false, evolve))
	b.add_theme_stylebox_override("hover", _card_style(accent, true, evolve))
	b.add_theme_stylebox_override("pressed", _card_style(accent, true, evolve))
	b.add_theme_stylebox_override("focus", _card_style(accent, true, evolve))

	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 20)
	m.add_theme_constant_override("margin_top", 22)
	b.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(v)

	# 頂列：按鍵徽章 + 標籤
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	var badge := PanelContainer.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = accent.darkened(0.35)
	bsb.border_color = accent.lightened(0.3)
	bsb.set_border_width_all(3)
	bsb.set_corner_radius_all(30)
	bsb.content_margin_left = 0
	bsb.content_margin_right = 0
	bsb.content_margin_top = 0
	bsb.content_margin_bottom = 0
	badge.add_theme_stylebox_override("panel", bsb)
	badge.custom_minimum_size = Vector2(60.0, 60.0)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var kl := Label.new()
	kl.text = key_name
	_style(kl, 34, Color.WHITE)
	kl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	kl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(kl)
	top.add_child(badge)
	var tcol := VBoxContainer.new()
	tcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tcol.alignment = BoxContainer.ALIGNMENT_CENTER
	tcol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(tcol)
	tcol.add_child(_skill_chip(tag, accent))
	var num := Label.new()
	num.text = "點選此卡" if Save.touch_mode else "按 %d 選擇" % (i + 1)
	_style(num, 15, Color(0.7, 0.7, 0.76))
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tcol.add_child(num)

	# 技能名稱
	var nm := Label.new()
	nm.text = SkillDB.display_name(id, evolve or Game.is_evolved(id))
	_style(nm, 36, accent.lightened(0.55))
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(nm)

	# 等級點
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 6)
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(pips)
	for p in SkillDB.MAX_LEVEL:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(34.0, 8.0)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if evolve or p < new_lv:
			pip.color = accent
			if not evolve and p == new_lv - 1 and kind != "learn":
				pip.color = Color.WHITE   # 本次提升的那一格
		else:
			pip.color = Color(0.25, 0.22, 0.24)
		pips.add_child(pip)

	var d := Label.new()
	d.text = info["desc"]
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(220.0 if Save.touch_mode else 250.0, 0.0)
	_style(d, 19, Color(0.86, 0.86, 0.9))
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(d)

	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(grow)

	# 效果框
	var eff := PanelContainer.new()
	var esb := StyleBoxFlat.new()
	esb.bg_color = Color(0.0, 0.0, 0.0, 0.45)
	esb.border_color = Color(accent.r, accent.g, accent.b, 0.6)
	esb.set_border_width_all(1)
	esb.set_corner_radius_all(10)
	esb.content_margin_left = 12
	esb.content_margin_right = 12
	esb.content_margin_top = 8
	esb.content_margin_bottom = 10
	eff.add_theme_stylebox_override("panel", esb)
	eff.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(eff)
	var ev := VBoxContainer.new()
	ev.mouse_filter = Control.MOUSE_FILTER_IGNORE
	eff.add_child(ev)
	var eh := Label.new()
	eh.text = detail_head
	_style(eh, 15, accent.lightened(0.2))
	eh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ev.add_child(eh)
	var et := Label.new()
	et.text = detail
	et.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	et.custom_minimum_size = Vector2(210.0 if Save.touch_mode else 240.0, 0.0)
	_style(et, 19, Color.WHITE)
	et.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ev.add_child(et)

	b.pressed.connect(_pick_skill.bind(i))
	b.resized.connect(func() -> void: b.pivot_offset = b.size * 0.5)
	b.mouse_entered.connect(func() -> void:
		b.create_tween().tween_property(b, "scale", Vector2.ONE * 1.04, 0.12))
	b.mouse_exited.connect(func() -> void:
		b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.12))
	b.focus_entered.connect(func() -> void:
		b.create_tween().tween_property(b, "scale", Vector2.ONE * 1.04, 0.12))
	b.focus_exited.connect(func() -> void:
		b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.12))
	return b


func _open_skill_pick(wave_done: int) -> void:
	var opts := Game.skill_options(3)
	if opts.is_empty():
		return
	pending_options = opts
	skill_title.text = "選擇技能" if wave_done == 0 else "第 %d 波完成" % wave_done
	skill_sub.text = "選一項強化　點選卡片　·　技能列在畫面左上，點擊即可施放" if Save.touch_mode else "選一項強化　按 1 / 2 / 3 或點擊卡片　·　技能以 Z X C V B 施放"
	for c in skill_cards.get_children():
		c.queue_free()
	for i in opts.size():
		var card := _make_skill_card(i, opts[i])
		skill_cards.add_child(card)
		# 依序淡入
		card.modulate.a = 0.0
		var tw := card.create_tween()
		tw.tween_interval(0.08 * i)
		tw.tween_property(card, "modulate:a", 1.0, 0.22)
	var card_list: Array = skill_cards.get_children().filter(func(c: Node) -> bool: return not c.is_queued_for_deletion())
	_guard_buttons(card_list, 0.5)
	Game.set_state(Game.State.SKILL)
	await get_tree().process_frame
	if skill_cards.get_child_count() > 0:
		(skill_cards.get_child(0) as Control).grab_focus()


func _pick_skill(i: int) -> void:
	if Game.state != Game.State.SKILL or i >= pending_options.size():
		return
	var opt: Dictionary = pending_options[i]
	Game.choose_skill(opt)
	pending_options = []
	Sfx.play("pickup")
	Game.set_state(Game.State.PLAYING)
	var id: String = opt["id"]
	if opt["kind"] == "evolve":
		_show_banner("突破！" + SkillDB.display_name(id, true))
	else:
		_show_banner("%s Lv%d" % [SkillDB.display_name(id, false), Game.skill_level(id)])


# ---------- 技能列 ----------

func _build_skill_bar() -> void:
	skill_bar = HBoxContainer.new()
	skill_bar.add_theme_constant_override("separation", 10)
	skill_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(skill_bar)
	_place(skill_bar, 0.5, 1.0, -240.0, -104.0, 240.0, -16.0)
	skill_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH

	for i in SkillDB.ORDER.size():
		var id: String = SkillDB.ORDER[i]
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(slot_px, slot_px)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		skill_bar.add_child(slot)

		var panel := Panel.new()
		panel.set_anchors_preset(Control.PRESET_FULL_RECT)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.05, 0.05, 0.08, 0.78)
		sb.border_color = SkillDB.SKILLS[id]["color"]
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(8)
		panel.add_theme_stylebox_override("panel", sb)
		slot.add_child(panel)

		var cd := ColorRect.new()
		cd.color = Color(0.0, 0.0, 0.0, 0.7)
		cd.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(cd)

		var key := Label.new()
		key.text = SkillDB.KEY_NAMES[i]
		var k := slot_px / 88.0
		_style(key, int(22 * k), Color(1.0, 0.9, 0.5))
		key.position = Vector2(8, 2) * k
		slot.add_child(key)

		var nm := Label.new()
		_style(nm, int(17 * k), Color.WHITE)
		nm.position = Vector2(0, 30) * k
		nm.size = Vector2(slot_px, 24 * k)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot.add_child(nm)

		var lvl := Label.new()
		_style(lvl, int(16 * k), SkillDB.SKILLS[id]["color"])
		lvl.position = Vector2(0, 60) * k
		lvl.size = Vector2(slot_px, 24 * k)
		lvl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot.add_child(lvl)

		var cdl := Label.new()
		_style(cdl, int(30 * k), Color.WHITE)
		cdl.position = Vector2(0, 26) * k
		cdl.size = Vector2(slot_px, 40 * k)
		cdl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot.add_child(cdl)

		skill_slots.append({"root": slot, "cd": cd, "name": nm, "lvl": lvl, "cdl": cdl, "panel": panel})


func _update_skill_bar() -> void:
	if skills_node == null or not is_instance_valid(skills_node):
		skills_node = get_node_or_null("/root/Main/Skills")
	for i in skill_slots.size():
		var slot: Dictionary = skill_slots[i]
		var id: String = SkillDB.ORDER[i]
		var lv := Game.skill_level(id)
		var evo := Game.is_evolved(id)
		var root: Control = slot["root"]
		var cd: ColorRect = slot["cd"]
		var cdl: Label = slot["cdl"]
		if lv == 0:
			(slot["name"] as Label).text = "未習得"
			(slot["lvl"] as Label).text = ""
			root.modulate.a = 0.4
			cd.size = Vector2.ZERO
			cdl.text = ""
			(slot["name"] as Label).modulate.a = 1.0
			continue
		root.modulate.a = 1.0
		(slot["name"] as Label).text = SkillDB.display_name(id, evo)
		(slot["lvl"] as Label).text = "★突破" if evo else "Lv%d" % lv
		var frac := 0.0
		var remain := 0.0
		if skills_node != null:
			frac = skills_node.cooldown_fraction(id)
			remain = float(skills_node.cooldowns[id])
		cd.position = Vector2(0, slot_px * (1.0 - frac))
		cd.size = Vector2(slot_px, slot_px * frac)
		cdl.text = "%d" % ceili(remain) if remain > 0.0 else ""
		(slot["name"] as Label).modulate.a = 0.0 if remain > 0.0 else 1.0


# ---------- 大逃殺 HUD ----------

func _build_br_hud() -> void:
	minimap = Minimap.new()
	minimap.visible = Game.is_br()
	add_child(minimap)
	minimap.anchor_left = 0.0
	minimap.anchor_top = 0.0
	minimap.anchor_right = 0.0
	minimap.anchor_bottom = 0.0
	minimap.offset_left = 20.0
	minimap.offset_top = 20.0
	minimap.offset_right = 190.0
	minimap.offset_bottom = 190.0

	feed_box = VBoxContainer.new()
	feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feed_box.visible = Game.is_br()
	add_child(feed_box)
	feed_box.anchor_left = 1.0
	feed_box.anchor_right = 1.0
	feed_box.anchor_top = 0.0
	feed_box.anchor_bottom = 0.0
	feed_box.offset_left = -360.0
	feed_box.offset_right = -24.0
	feed_box.offset_top = 120.0
	feed_box.offset_bottom = 300.0
	feed_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN


func _on_kill_feed(text: String) -> void:
	if feed_box == null:
		return
	var l := Label.new()
	l.text = text
	_style(l, 18, Color(1.0, 0.92, 0.7))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feed_box.add_child(l)
	while feed_box.get_child_count() > 5:
		feed_box.get_child(0).queue_free()
		feed_box.remove_child(feed_box.get_child(0))
	var tw := l.create_tween()
	tw.tween_interval(5.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)


# ---------- 手機版面 ----------

func _touch_layout() -> void:
	# 手機版面：左下搖桿、右下按鍵，資訊集中在上方與下方中央，避開安全區
	var ins := UIUtil.safe_insets(self)
	var cx := 0.5
	# 下方中央：武器/彈藥/血量（大逃殺的武器欄由觸控層繪製）
	var base := -(ins.w + (66.0 if Game.is_br() else 20.0))
	_place(health_bar, cx, 1.0, -150.0, base - 12.0, 150.0, base)
	_place(shield_bar, cx, 1.0, -150.0, base - 18.0, 150.0, base - 12.0)
	shield_bar.z_index = 1
	_place(health_label, cx, 1.0, -150.0, base - 48.0, 150.0, base - 20.0)
	health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style(health_label, 20)
	_place(ammo_label, cx, 1.0, -150.0, base - 96.0, 150.0, base - 48.0)
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style(ammo_label, 30)
	_place(weapon_label, cx, 1.0, -150.0, base - 122.0, 150.0, base - 98.0)
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	weapon_label.visible = not Game.is_br()

	# 上方中央：關卡 / 波次資訊
	_style(wave_label, 24)
	_place(wave_label, cx, 0.0, -240.0, ins.y + 6.0, 240.0, ins.y + 40.0)
	_style(enemy_label, 17, Color(0.82, 0.68, 0.62))
	_place(enemy_label, cx, 0.0, -260.0, ins.y + 40.0, 260.0, ins.y + 64.0)

	# 右上 / 左上
	if Game.is_br():
		minimap.anchor_left = 1.0
		minimap.anchor_right = 1.0
		minimap.offset_left = -(ins.z + 150.0)
		minimap.offset_right = -ins.z
		minimap.offset_top = ins.y + 6.0
		minimap.offset_bottom = ins.y + 156.0
		minimap.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		feed_box.offset_left = -(ins.z + 340.0)
		feed_box.offset_right = -(ins.z + 4.0)
		feed_box.offset_top = ins.y + 164.0
		feed_box.offset_bottom = ins.y + 300.0
		# 戰績放在暫停鈕下方
		_place(score_label, 0.0, 0.0, ins.x + 10.0, ins.y + 72.0, ins.x + 220.0, ins.y + 130.0)
		score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	else:
		_place(score_label, 1.0, 0.0, -(ins.z + 220.0), ins.y + 8.0, -(ins.z + 8.0), ins.y + 90.0)
		_style(score_label, 18)
		# 技能列移到左上、暫停鈕右側
		_place(skill_bar, 0.0, 0.0, ins.x + 76.0, ins.y + 8.0, ins.x + 76.0 + slot_px * 5.0 + 40.0, ins.y + 8.0 + slot_px)
		skill_bar.add_theme_constant_override("separation", 8)
	_style(pickup_hint, 20, Color(0.85, 0.78, 0.5))
	_place(pickup_hint, cx, 1.0, -220.0, base - 160.0, 220.0, base - 128.0)
	pickup_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
