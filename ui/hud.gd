extends CanvasLayer

const MenuUI = preload("res://ui/menu_ui.gd")
const SkillDB = preload("res://scripts/data/skill_db.gd")
const WeaponDB = preload("res://scripts/data/weapon_db.gd")
const EquipDB = preload("res://scripts/data/equip_db.gd")
const LevelDB = preload("res://scripts/data/level_db.gd")
const Minimap = preload("res://ui/minimap.gd")
const TouchControls = preload("res://ui/touch_controls.gd")
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
var menu_body: Label
var button_box: VBoxContainer
var menu_ui: Control
var skill_root: Control
var skill_title: Label
var skill_sub: Label
var skill_cards: HBoxContainer
var pending_options: Array = []
var skill_slots: Array = []
var skill_bar: HBoxContainer
var weapon_label: Label
var skills_node: Node = null
var hud_items: Array = []
var minimap: Control
var feed_box: VBoxContainer
var br_node: Node = null
var banner_tween: Tween
var hit_tween: Tween
var damage_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.reset()

	player = get_tree().get_first_node_in_group("player")
	if player != null and player.has_signal("damaged"):
		player.damaged.connect(_on_player_damaged)

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
	Game.skill_cast.connect(_on_skill_cast)
	Game.banner.connect(_show_banner)
	Game.kill_feed.connect(_on_kill_feed)

	var weapon_node := get_node_or_null("/root/Main/Player/Head/Camera3D/Weapon")
	if weapon_node != null:
		weapon_node.update_ammo_ui()

	if Game.skip_menu:
		Game.skip_menu = false
		_begin_run()
	else:
		_on_state_changed(Game.State.MENU)
		Game.show_lobby = false


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


func _process(_delta: float) -> void:
	if player != null and is_instance_valid(player):
		health_bar.max_value = player.max_health
		health_bar.value = player.health
	if Game.is_br():
		if br_node == null:
			br_node = get_node_or_null("/root/Main/BR")
		wave_label.text = "存活 %d / %d" % [Game.br_alive, Game.BR_PLAYERS]
		if br_node != null and bool(br_node.get("started")):
			enemy_label.text = "%s　圈外傷害 %d/秒" % [br_node.zone_text(), int(br_node.zone_dps())]
		else:
			enemy_label.text = "準備中…"
		score_label.text = "擊殺：%d\n喪屍幣 +%d" % [Game.kills, Game.run_coins]
	else:
		wave_label.text = "第 %d 關　第 %d / %d 波" % [Game.level, maxi(Game.wave, 1), Game.total_waves]
		enemy_label.text = "剩餘敵人：%d" % Game.enemies_remaining
		score_label.text = "分數：%d\n擊殺：%d\n喪屍幣 +%d" % [Game.score, Game.kills, Game.run_coins]
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
	bg.color = Color(0.0, 0.0, 0.0, 0.72)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_root.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_root.add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)

	menu_title = Label.new()
	_style(menu_title, 60, Color(0.85, 0.76, 0.58))
	menu_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(menu_title)

	menu_body = Label.new()
	_style(menu_body, 22)
	menu_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_body.custom_minimum_size = Vector2(680.0, 0.0)
	box.add_child(menu_body)

	button_box = VBoxContainer.new()
	button_box.add_theme_constant_override("separation", 10)
	box.add_child(button_box)


func _set_buttons(items: Array) -> void:
	for c in button_box.get_children():
		c.queue_free()
	for item in items:
		var b := Button.new()
		b.text = item[0]
		b.custom_minimum_size = Vector2(260.0, 48.0)
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(item[1])
		button_box.add_child(b)


# ---------- 狀態與事件 ----------

func _on_state_changed(s: int) -> void:
	var in_menu := s == Game.State.MENU
	var settings_open: bool = menu_ui != null and menu_ui.pause_mode
	menu_root.visible = (s == Game.State.PAUSED or s == Game.State.WON or s == Game.State.LOST) and not settings_open
	skill_root.visible = s == Game.State.SKILL
	if menu_ui != null:
		if in_menu:
			menu_ui.open_main(Game.show_lobby)
		else:
			menu_ui.visible = settings_open and s == Game.State.PAUSED
	for n in hud_items:
		(n as CanvasItem).visible = not in_menu

	match s:
		Game.State.PAUSED:
			menu_title.text = "暫停"
			menu_body.text = ""
			_set_buttons([["繼續", _on_resume], ["設定", _on_open_settings], ["重新開始", _on_restart], ["回遊戲大廳", _on_main_menu], ["離開", _on_quit]])
		Game.State.WON:
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
			menu_title.text = "你被淘汰了" if Game.is_br() else "你已陣亡"
			menu_body.text = _summary()
			_set_buttons([["重新開始", _on_restart], ["回遊戲大廳", _on_main_menu], ["離開", _on_quit]])

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
		return "\n".join(lines)
	var record := "　★ 新紀錄！" if Game.score >= int(Save.level_best.get(str(Game.level), 0)) and Game.score > 0 else ""
	var lines2: PackedStringArray = []
	lines2.append("「%s」　撐到第 %d 波" % [Game.level_cfg["name"], maxi(Game.wave, 1)])
	lines2.append("擊殺 %d　分數 %d%s" % [Game.kills, Game.score, record])
	var bonus := int(r.get("clear_bonus", 0))
	lines2.append("本局喪屍幣 +%d%s（持有 %d）" % [Game.run_coins, "　首次通關獎勵 +%d" % bonus if bonus > 0 else "", Save.coins])
	lines2.append("關卡排行榜名次：第 %d 名" % Game.last_rank)
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


func _on_hit_marker(killed: bool) -> void:
	if hit_tween:
		hit_tween.kill()
	hit_marker.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2) if killed else Color.WHITE)
	hit_marker.modulate.a = 1.0
	hit_tween = create_tween()
	hit_tween.tween_property(hit_marker, "modulate:a", 0.0, 0.15)


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
	bg.color = Color(0.0, 0.0, 0.0, 0.78)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	skill_root.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	skill_root.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)

	skill_title = Label.new()
	_style(skill_title, 48, Color(0.85, 0.74, 0.5))
	skill_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(skill_title)
	skill_sub = Label.new()
	_style(skill_sub, 22, Color(0.85, 0.85, 0.9))
	skill_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(skill_sub)

	skill_cards = HBoxContainer.new()
	skill_cards.add_theme_constant_override("separation", 22)
	skill_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(skill_cards)


func _card_style(accent: Color, hover: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = accent.darkened(0.7) if not hover else accent.darkened(0.5)
	sb.border_color = accent
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	return sb


func _open_skill_pick(wave_done: int) -> void:
	var opts := Game.skill_options(3)
	if opts.is_empty():
		return
	pending_options = opts
	skill_title.text = "選擇技能" if wave_done == 0 else "第 %d 波完成" % wave_done
	skill_sub.text = "選一項強化　（按 1 / 2 / 3 或點擊卡片）　技能以 Z X C V B 施放"
	for c in skill_cards.get_children():
		c.queue_free()
	for i in opts.size():
		var opt: Dictionary = opts[i]
		var id: String = opt["id"]
		var info: Dictionary = SkillDB.SKILLS[id]
		var key_name: String = SkillDB.KEY_NAMES[SkillDB.ORDER.find(id)]
		var lv := Game.skill_level(id)
		var accent: Color = info["color"]
		var head := ""
		var body := ""
		match opt["kind"]:
			"learn":
				head = "新技能"
				body = "%s\n\nLv1：%s" % [info["desc"], SkillDB.level_desc(id, 1, false)]
			"upgrade":
				head = "升級　Lv%d → Lv%d" % [lv, lv + 1]
				body = "%s\n\nLv%d：%s" % [info["desc"], lv + 1, SkillDB.level_desc(id, lv + 1, false)]
			"evolve":
				head = "★ 突破：%s ★" % info["evo_name"]
				body = "已達最高等級！\n\n%s" % SkillDB.level_desc(id, lv, true)
				accent = Color(1.0, 0.82, 0.3)
		var b := Button.new()
		b.text = "[%d]\n【%s】%s\n%s\n\n%s" % [i + 1, key_name, SkillDB.display_name(id, Game.is_evolved(id)), head, body]
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(290, 300)
		b.add_theme_font_size_override("font_size", 20)
		b.add_theme_color_override("font_color", Color.WHITE)
		b.add_theme_stylebox_override("normal", _card_style(accent, false))
		b.add_theme_stylebox_override("hover", _card_style(accent, true))
		b.add_theme_stylebox_override("pressed", _card_style(accent, true))
		b.add_theme_stylebox_override("focus", _card_style(accent, true))
		b.pressed.connect(_pick_skill.bind(i))
		skill_cards.add_child(b)
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
		slot.custom_minimum_size = Vector2(88, 88)
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
		_style(key, 22, Color(1.0, 0.9, 0.5))
		key.position = Vector2(8, 2)
		slot.add_child(key)

		var nm := Label.new()
		_style(nm, 17, Color.WHITE)
		nm.position = Vector2(0, 30)
		nm.size = Vector2(88, 24)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot.add_child(nm)

		var lvl := Label.new()
		_style(lvl, 16, SkillDB.SKILLS[id]["color"])
		lvl.position = Vector2(0, 60)
		lvl.size = Vector2(88, 24)
		lvl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot.add_child(lvl)

		var cdl := Label.new()
		_style(cdl, 30, Color.WHITE)
		cdl.position = Vector2(0, 26)
		cdl.size = Vector2(88, 40)
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
		cd.position = Vector2(0, 88.0 * (1.0 - frac))
		cd.size = Vector2(88, 88.0 * frac)
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
	# 右下角留給操作按鈕：彈藥與槍名移到左下
	_place(ammo_label, 0.0, 1.0, 24.0, -140.0, 324.0, -96.0)
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_place(weapon_label, 0.0, 1.0, 24.0, -180.0, 424.0, -146.0)
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
