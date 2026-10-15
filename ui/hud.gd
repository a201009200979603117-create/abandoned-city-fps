extends CanvasLayer
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

	Game.state_changed.connect(_on_state_changed)
	Game.wave_started.connect(_on_wave_started)
	Game.wave_cleared.connect(_on_wave_cleared)
	Game.hit_marker.connect(_on_hit_marker)

	if Game.skip_menu:
		Game.skip_menu = false
		Game.set_state(Game.State.PLAYING)
	else:
		_on_state_changed(Game.State.MENU)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if Game.state == Game.State.PLAYING:
			Game.set_state(Game.State.PAUSED)
		elif Game.state == Game.State.PAUSED:
			Game.set_state(Game.State.PLAYING)


func _process(_delta: float) -> void:
	if player != null and is_instance_valid(player):
		health_bar.max_value = player.max_health
		health_bar.value = player.health
	wave_label.text = "第 %d / %d 波" % [maxi(Game.wave, 1), Game.total_waves]
	enemy_label.text = "剩餘敵人：%d" % Game.enemies_remaining
	score_label.text = "分數：%d\n擊殺：%d" % [Game.score, Game.kills]


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
	fill.bg_color = Color(0.8, 0.15, 0.15)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.0, 0.0, 0.0, 0.6)
	health_bar.add_theme_stylebox_override("fill", fill)
	health_bar.add_theme_stylebox_override("background", back)
	add_child(health_bar)
	_place(health_bar, 0.0, 1.0, 24.0, -44.0, 324.0, -24.0)

	_style(ammo_label, 34)
	_place(ammo_label, 1.0, 1.0, -324.0, -84.0, -24.0, -34.0)
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_style(crosshair, 28)
	_style(pickup_hint, 22, Color(1.0, 0.9, 0.4))

	wave_label = _make_label(30)
	_place(wave_label, 0.5, 0.0, -200.0, 16.0, 200.0, 56.0)
	enemy_label = _make_label(20, Color(1.0, 0.8, 0.8))
	_place(enemy_label, 0.5, 0.0, -200.0, 58.0, 200.0, 88.0)

	score_label = _make_label(22, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	_place(score_label, 1.0, 0.0, -324.0, 16.0, -24.0, 80.0)

	banner = _make_label(48, Color(1.0, 0.9, 0.6))
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
	_style(menu_title, 60, Color(0.95, 0.85, 0.6))
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
	var playing := s == Game.State.PLAYING
	menu_root.visible = not playing

	match s:
		Game.State.MENU:
			menu_title.text = "廢棄城市 FPS"
			menu_body.text = "感染者佔領了這座城市，撐過 %d 波攻擊活下去。\n\nWASD 移動　Shift 奔跑　空白鍵 跳躍\n滑鼠 瞄準　左鍵 射擊　R 換彈　E 拾取　Esc 暫停" % Game.total_waves
			_set_buttons([["開始遊戲", _on_start], ["離開", _on_quit]])
		Game.State.PAUSED:
			menu_title.text = "暫停"
			menu_body.text = ""
			_set_buttons([["繼續", _on_resume], ["重新開始", _on_restart], ["離開", _on_quit]])
		Game.State.WON:
			menu_title.text = "任務完成！"
			menu_body.text = _summary()
			_set_buttons([["再玩一次", _on_restart], ["離開", _on_quit]])
		Game.State.LOST:
			menu_title.text = "你已陣亡"
			menu_body.text = _summary()
			_set_buttons([["重新開始", _on_restart], ["離開", _on_quit]])

	if button_box.get_child_count() > 0 and not playing:
		# 等按鈕重建完成後聚焦，方便鍵盤操作
		await get_tree().process_frame
		if button_box.get_child_count() > 0:
			(button_box.get_child(0) as Control).grab_focus()


func _summary() -> String:
	return "撐到第 %d 波\n擊殺 %d　分數 %d" % [maxi(Game.wave, 1), Game.kills, Game.score]


func _on_start() -> void:
	Game.set_state(Game.State.PLAYING)


func _on_resume() -> void:
	Game.set_state(Game.State.PLAYING)


func _on_restart() -> void:
	Game.skip_menu = true
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_quit() -> void:
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
