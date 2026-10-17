extends Control
# 主選單：封面、槍枝選擇、抽獎、排行榜、設定。全部以程式建立。

const WeaponDB = preload("res://scripts/data/weapon_db.gd")
const Leaderboard = preload("res://scripts/data/leaderboard.gd")
const CoverArt = preload("res://ui/cover_art.gd")
const EquipDB = preload("res://scripts/data/equip_db.gd")
const LevelDB = preload("res://scripts/data/level_db.gd")
const UIUtil = preload("res://ui/ui_util.gd")
const IconRect = preload("res://ui/icon_rect.gd")
const ProgressDB = preload("res://scripts/data/progress_db.gd")
const TouchEditor = preload("res://ui/touch_layout_editor.gd")
const Weather = preload("res://scripts/systems/weather.gd")

const PAGE_PARENT: Dictionary = {
	"lobby": "main", "weapons": "lobby", "gacha": "lobby", "leaderboard": "lobby",
	"levels": "lobby", "br": "lobby", "equipment": "lobby", "quests": "lobby", "touch_edit": "settings",
}

signal start_requested
signal quit_requested
signal closed   # 從暫停選單開啟設定後關閉

const ACCENT: Color = Color(0.78, 0.34, 0.2)
const GOLD: Color = Color(0.82, 0.68, 0.34)
const PANEL_BG: Color = Color(0.05, 0.045, 0.04, 0.88)

var art: Control
var page_root: Control
var coin_label: Label
var title_label: Label
var current_page: String = "main"
var pause_mode: bool = false
var preview_pivot: Node3D
var busy: bool = false
var confirm_reset: bool = false
var settings_return: String = "main"
var sel_level: int = 1
var eq_slot: String = "head"
var lb_mode: String = "zombie"
var t: float = 0.0
var mobile: bool:
	get:
		return Save.touch_mode


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	art = CoverArt.new()
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(art)
	page_root = Control.new()
	page_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(page_root)
	show_page("main")


func _process(delta: float) -> void:
	if not visible:
		return
	t += delta
	if is_instance_valid(preview_pivot):
		preview_pivot.rotate_y(delta * 0.9)
	if is_instance_valid(coin_label):
		var coin_text := "喪屍幣　%d" % Save.coins
		if coin_label.text != coin_text:
			coin_label.text = coin_text
	if is_instance_valid(title_label):
		# 偶爾閃爍的霓虹招牌
		var flick := 1.0 if sin(t * 17.0) * sin(t * 5.3) > -0.93 else 0.55
		title_label.modulate.a = flick


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_visible_in_tree():
		if current_page == "main" and not pause_mode:
			quit_requested.emit()
		else:
			_back()


func open_main(to_lobby: bool = false) -> void:
	pause_mode = false
	visible = true
	show_page("lobby" if to_lobby else "main")


func open_settings_from_pause() -> void:
	pause_mode = true
	visible = true
	show_page("settings")


# ---------- 共用元件 ----------

func _label(text: String, size: int, color: Color = Color.WHITE, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", maxi(size / 8, 2))
	l.horizontal_alignment = align
	return l


func _box(bg: Color, border: Color, border_w: int = 2, radius: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


func _panel(min_size: Vector2 = Vector2.ZERO, border: Color = Color(0.5, 0.2, 0.18, 0.9)) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = min_size
	p.add_theme_stylebox_override("panel", _box(PANEL_BG, border, 2, 10))
	return p


func _button(text: String, cb: Callable, min_size: Vector2 = Vector2(300, 52), accent: Color = ACCENT, selected: bool = false, icon: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_size.x, maxf(min_size.y, 62.0) if mobile else min_size.y)
	b.add_theme_font_size_override("font_size", 25 if mobile else 22)
	b.add_theme_color_override("font_color", Color(0.92, 0.9, 0.88))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(0.45, 0.45, 0.48))
	var base := Color(0.12, 0.08, 0.1, 0.88)
	if selected:
		base = accent.darkened(0.55)
		base.a = 0.95
	b.add_theme_stylebox_override("normal", _box(base, accent if selected else accent.darkened(0.5), 3 if selected else 2, 8))
	b.add_theme_stylebox_override("hover", _box(accent.darkened(0.6), accent.lightened(0.2), 3, 8))
	b.add_theme_stylebox_override("pressed", _box(accent.darkened(0.3), Color.WHITE, 3, 8))
	b.add_theme_stylebox_override("focus", _box(accent.darkened(0.6), accent.lightened(0.2), 3, 8))
	b.add_theme_stylebox_override("disabled", _box(Color(0.08, 0.08, 0.1, 0.8), Color(0.2, 0.2, 0.24), 2, 8))
	if icon != "":
		# 圖示放在左側，文字留出空間
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			(b.get_theme_stylebox(st) as StyleBoxFlat).content_margin_left = 54
		var px := 30.0 if mobile else 26.0
		var ic := IconRect.make(icon, accent.lightened(0.5), px)
		ic.set_anchors_preset(Control.PRESET_CENTER_LEFT)
		ic.offset_left = 16
		ic.offset_right = 16 + px
		ic.offset_top = -px * 0.5
		ic.offset_bottom = px * 0.5
		b.add_child(ic)
	b.pressed.connect(func() -> void: Sfx.play("ui_click", -4.0))
	if not mobile:
		b.mouse_entered.connect(func() -> void:
			if not b.disabled:
				Sfx.play("ui_hover", -10.0))
	if not cb.is_null():
		b.pressed.connect(cb)
	return b


func _clear_page() -> void:
	coin_label = null
	title_label = null
	preview_pivot = null
	page_root.modulate.a = 1.0
	for c in page_root.get_children():
		c.queue_free()


func _coin_panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(Color(0.06, 0.05, 0.03, 0.9), GOLD.darkened(0.2), 2, 20))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	p.add_child(h)
	# 等級與經驗條
	var lv := Save.player_level()
	var base_xp := ProgressDB.xp_at(lv)
	var next_xp := ProgressDB.xp_at(lv + 1)
	var lv_box := HBoxContainer.new()
	lv_box.add_theme_constant_override("separation", 8)
	h.add_child(lv_box)
	var star := IconRect.make("star", Color(0.55, 0.8, 1.0), 26)
	star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lv_box.add_child(star)
	var lv_col := VBoxContainer.new()
	lv_col.add_theme_constant_override("separation", 0)
	lv_box.add_child(lv_col)
	lv_col.add_child(_label("Lv.%d" % lv, 20, Color(0.7, 0.88, 1.0)))
	var xb := _quest_bar(float(Save.xp - base_xp), float(next_xp - base_xp), Color(0.4, 0.7, 1.0))
	xb.custom_minimum_size = Vector2(86, 8)
	lv_col.add_child(xb)
	var coin_ic := IconRect.make("coin", GOLD, 24)
	coin_ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(coin_ic)
	coin_label = _label("喪屍幣　%d" % Save.coins, 24, GOLD)
	h.add_child(coin_label)
	return p


# 子頁面骨架：標題列（含喪屍幣）+ 內容 + 返回鈕。回傳內容容器
func _page_frame(title: String, scrollable: bool = true) -> VBoxContainer:
	if mobile:
		return _mobile_frame(title)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	page_root.add_child(margin)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.02, 0.78) if pause_mode else Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_root.add_child(dim)
	page_root.move_child(dim, 0)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)
	var tl := _label(title, 44, Color(0.98, 0.85, 0.6))
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(tl)
	if not pause_mode:
		header.add_child(_coin_panel())

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	if scrollable:
		# 內容超過視窗高度時可捲動
		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		root.add_child(scroll)
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(content)
	else:
		content.size_flags_vertical = Control.SIZE_EXPAND_FILL
		root.add_child(content)

	var footer := HBoxContainer.new()
	root.add_child(footer)
	footer.add_child(_button("◀ 返回", _back, Vector2(200, 48)))
	return content


func _back() -> void:
	Save.save()
	gacha_last = {}
	confirm_reset = false
	if pause_mode:
		pause_mode = false
		visible = false
		closed.emit()
	elif current_page == "settings":
		show_page(settings_return)
	else:
		show_page(str(PAGE_PARENT.get(current_page, "main")))


func show_page(page: String) -> void:
	current_page = page
	if art != null:
		art.visible = not pause_mode
	_clear_page()
	match page:
		"main":
			if mobile:
				_page_main_mobile()
			else:
				_page_main()
		"lobby":
			if mobile:
				_page_lobby_mobile()
			else:
				_page_lobby()
		"levels":
			_page_levels()
		"br":
			_page_br()
		"equipment":
			_page_equipment()
		"weapons":
			_page_weapons()
		"gacha":
			_page_gacha()
		"leaderboard":
			_page_leaderboard()
		"quests":
			_page_quests()
		"touch_edit":
			_page_touch_edit()
		"settings":
			_page_settings()


# ---------- 主頁（封面） ----------

func _page_main() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 70)
	margin.add_theme_constant_override("margin_top", 34)
	margin.add_theme_constant_override("margin_bottom", 30)
	margin.add_theme_constant_override("margin_right", 40)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_root.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)

	col.add_child(_label("SURVIVE　·　FIGHT　·　EVOLVE", 18, Color(0.9, 0.6, 0.5, 0.9)))

	# 標題：紅色陰影層 + 主標
	var title_box := Control.new()
	title_box.custom_minimum_size = Vector2(500, 98)
	title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(title_box)
	var shadow := _label("廢棄城市", 92, Color(0.55, 0.02, 0.02))
	shadow.position = Vector2(5, 6)
	title_box.add_child(shadow)
	title_label = _label("廢棄城市", 92, Color(0.82, 0.74, 0.6))
	title_label.add_theme_constant_override("outline_size", 12)
	title_label.add_theme_color_override("font_outline_color", Color(0.45, 0.04, 0.02))
	title_box.add_child(title_label)
	col.add_child(_label("ABANDONED CITY　FPS", 26, Color(0.95, 0.5, 0.35)))

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(spacer)

	var first := _button("開始遊戲", func() -> void: show_page("lobby"), Vector2(330, 58), GOLD, false, "play")
	col.add_child(first)
	col.add_child(_button("設定", _open_settings.bind("main"), Vector2(330, 48), Color(0.6, 0.65, 0.7), false, "gear"))
	if not OS.has_feature("web"):
		col.add_child(_button("離開", func() -> void: quit_requested.emit(), Vector2(330, 48), Color(0.5, 0.5, 0.55)))

	var weapon: Dictionary = WeaponDB.WEAPONS[Save.selected_weapon]
	var skin: Dictionary = WeaponDB.SKINS[Save.selected_skin]
	var info := _label("目前裝備：%s　·　%s" % [weapon["name"], skin["name"]], 18, Color(0.85, 0.85, 0.9))
	col.add_child(info)
	col.add_child(_label("已通關 %d / %d 關　·　大逃殺勝場 %d" % [Save.cleared_level, LevelDB.count(), Save.br_wins], 18, Color(0.85, 0.85, 0.9)))

	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(grow)
	col.add_child(_label("累計擊殺 %d　·　最高單關分數 %d" % [Save.total_kills + Save.br_kills, Save.best_score], 18, Color(0.8, 0.75, 0.7)))
	col.add_child(_label("擊殺敵人可獲得喪屍幣，用來購買裝備或抽取槍枝皮膚", 16, Color(0.65, 0.65, 0.7)))

	# 右上角喪屍幣
	var coin := _coin_panel()
	page_root.add_child(coin)
	coin.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	coin.offset_left = -260
	coin.offset_right = -30
	coin.offset_top = 24
	coin.offset_bottom = 70
	coin.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	first.grab_focus.call_deferred()


# ---------- 3D 預覽 ----------

func _make_preview(weapon_id: String, skin_id: String, px: Vector2) -> SubViewportContainer:
	var c := SubViewportContainer.new()
	c.stretch = true
	c.custom_minimum_size = px
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_DISABLED if (mobile or Save.effective_quality() == 0) else Viewport.MSAA_2X
	vp.size = Vector2i(px)
	c.add_child(vp)

	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.65, 0.65, 0.8)
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)

	var cam := Camera3D.new()
	var pos := Vector3(0.0, 0.18, 1.35)
	cam.transform = Transform3D(Basis.looking_at(Vector3(0.0, -0.02, 0.0) - pos, Vector3.UP), pos)
	cam.fov = 36.0
	vp.add_child(cam)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, -30.0, 0.0)
	sun.light_energy = 1.5
	vp.add_child(sun)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-1.0, 0.6, 1.2)
	fill.light_energy = 1.2
	fill.omni_range = 6.0
	vp.add_child(fill)

	preview_pivot = Node3D.new()
	preview_pivot.rotation.y = 0.6
	vp.add_child(preview_pivot)
	WeaponDB.build_model(preview_pivot, weapon_id, skin_id)
	return c


# ---------- 槍枝選擇 ----------

func _stat_row(parent: Control, label_text: String, value: float, color: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var l := _label(label_text, 18, Color(0.85, 0.85, 0.9))
	l.custom_minimum_size = Vector2(70, 0)
	row.add_child(l)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = 100.0
	bar.value = clampf(value, 4.0, 100.0)
	bar.custom_minimum_size = Vector2(190, 16)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(4)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.0, 0.0, 0.0, 0.6)
	back.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", back)
	row.add_child(bar)


func _page_weapons() -> void:
	var content := _page_frame("槍枝選擇")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(row)

	# 左：槍枝清單
	var list_panel := _panel(Vector2(290, 0))
	row.add_child(list_panel)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	list_panel.add_child(list)
	for id in WeaponDB.ORDER:
		var def: Dictionary = WeaponDB.WEAPONS[id]
		var sel: bool = id == Save.selected_weapon
		var b := _button(("▶ " if sel else "　") + str(def["name"]), _select_weapon.bind(id), Vector2(260, 50), GOLD, sel)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		list.add_child(b)

	# 右：預覽、數值、皮膚
	var detail := _panel(Vector2(0, 0))
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(detail)
	var dcol := VBoxContainer.new()
	dcol.add_theme_constant_override("separation", 8)
	detail.add_child(dcol)

	var def: Dictionary = WeaponDB.WEAPONS[Save.selected_weapon]
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 20)
	dcol.add_child(top)
	top.add_child(_make_preview(Save.selected_weapon, Save.selected_skin, Vector2(360, 230)))

	var stats := VBoxContainer.new()
	stats.add_theme_constant_override("separation", 6)
	top.add_child(stats)
	stats.add_child(_label(str(def["name"]), 28, GOLD))
	var desc := _label(str(def["desc"]), 16, Color(0.8, 0.8, 0.85))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(280, 0)
	stats.add_child(desc)
	var dmg_total: float = float(def["damage"]) * float(def["pellets"])
	var rate: float = 1.0 / float(def["fire_rate"])
	_stat_row(stats, "傷害", dmg_total / 160.0 * 100.0, Color(1.0, 0.4, 0.3))
	_stat_row(stats, "射速", rate / 16.0 * 100.0, Color(1.0, 0.8, 0.3))
	_stat_row(stats, "彈量", float(def["mag"]) / 100.0 * 100.0, Color(0.5, 0.9, 0.5))
	_stat_row(stats, "射程", float(def["range"]) / 300.0 * 100.0, Color(0.4, 0.75, 1.0))
	_stat_row(stats, "穩定", 100.0 - float(def["recoil"]) * 800.0 - float(def["spread"]) * 5.0, Color(0.8, 0.5, 1.0))
	stats.add_child(_label("每秒傷害 %d　彈匣 %d　備彈 %d" % [int(dmg_total * rate), def["mag"], def["reserve"]], 16, Color(0.75, 0.75, 0.8)))

	# 配件改裝
	dcol.add_child(_label("配件改裝（用喪屍幣升級，每把槍各自獨立）", 18, Color(0.9, 0.85, 0.7)))
	for kind in ProgressDB.ATTACH_KINDS:
		var info: Dictionary = ProgressDB.ATTACH[kind]
		var lv := Save.attach_level(Save.selected_weapon, kind)
		var arow := HBoxContainer.new()
		arow.add_theme_constant_override("separation", 10)
		dcol.add_child(arow)
		var aic := IconRect.make("wrench", GOLD.lightened(0.2), 24)
		aic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		arow.add_child(aic)
		var an := _label(str(info["name"]), 18)
		an.custom_minimum_size = Vector2(130, 0)
		arow.add_child(an)
		var ad := _label(str(info["desc"]), 14, Color(0.72, 0.72, 0.8))
		ad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		arow.add_child(ad)
		for p in ProgressDB.ATTACH_MAX:
			var pip := ColorRect.new()
			pip.custom_minimum_size = Vector2(18, 8)
			pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			pip.color = GOLD if p < lv else Color(0.25, 0.22, 0.24)
			arow.add_child(pip)
		var cost := ProgressDB.attach_cost(kind, lv)
		var abtn: Button
		if lv >= ProgressDB.ATTACH_MAX:
			abtn = _button("滿級", Callable(), Vector2(130, 40), Color(0.5, 0.5, 0.55))
			abtn.disabled = true
		else:
			abtn = _button("升級 %d" % cost, _upgrade_attach.bind(kind), Vector2(130, 40), GOLD)
			abtn.disabled = Save.coins < cost
		abtn.add_theme_font_size_override("font_size", 17)
		arow.add_child(abtn)

	dcol.add_child(_label("槍枝皮膚（點選裝備，抽獎可獲得更多）", 18, Color(0.9, 0.85, 0.7)))
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	dcol.add_child(grid)
	for sid in WeaponDB.SKINS:
		var skin: Dictionary = WeaponDB.SKINS[sid]
		var rar: Dictionary = WeaponDB.RARITY[skin["rarity"]]
		var owned: bool = Save.owned_skins.has(sid)
		var is_sel: bool = sid == Save.selected_skin
		var txt: String = str(skin["name"]) if owned else "？？？"
		var sb := _button(txt, _select_skin.bind(sid), Vector2(138, 40), rar["color"], is_sel)
		sb.add_theme_font_size_override("font_size", 17)
		sb.disabled = not owned
		grid.add_child(sb)


func _upgrade_attach(kind: String) -> void:
	if Save.upgrade_attach(Save.selected_weapon, kind):
		Sfx.play("pickup", 0.0, 1.3)
		Game.record_max("attach_maxed", Save.attach_maxed_count())
	show_page("weapons")


func _select_weapon(id: String) -> void:
	Save.selected_weapon = id
	Save.save()
	show_page("weapons")


func _select_skin(id: String) -> void:
	if not Save.owned_skins.has(id):
		return
	Save.selected_skin = id
	Save.save()
	show_page("weapons")


# ---------- 抽獎 ----------

func _rarity_chances() -> String:
	var total := 0.0
	var by_rarity: Dictionary = {}
	for id in WeaponDB.SKINS:
		var r: String = WeaponDB.SKINS[id]["rarity"]
		var w: float = WeaponDB.RARITY[r]["weight"]
		total += w
		by_rarity[r] = float(by_rarity.get(r, 0.0)) + w
	var parts: PackedStringArray = []
	for r in ["common", "rare", "epic", "legendary"]:
		parts.append("%s %.1f%%" % [WeaponDB.RARITY[r]["name"], float(by_rarity[r]) / total * 100.0])
	return "　".join(parts)


var gacha_result: Label
var gacha_button: Button
var gacha_preview_holder: Control
var gacha_equip_holder: Control
var gacha_last: Dictionary = {}


func _gacha_text(res: Dictionary) -> String:
	var skin: Dictionary = WeaponDB.SKINS[res["skin"]]
	var rar: Dictionary = WeaponDB.RARITY[skin["rarity"]]
	if res.get("equipped", false):
		return "已裝備【%s】%s" % [rar["name"], skin["name"]]
	if res["duplicate"]:
		return "重複獲得【%s】%s
已返還 %d 枚喪屍幣" % [rar["name"], skin["name"], Save.DUPLICATE_REFUND]
	return "恭喜獲得新皮膚！
【%s】%s" % [rar["name"], skin["name"]]


func _page_gacha() -> void:
	busy = false
	var content := _page_frame("皮膚抽獎")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(row)

	# 左：抽獎台
	var stage := _panel(Vector2(520, 0), Color(0.55, 0.3, 0.8, 0.9))
	row.add_child(stage)
	var scol := VBoxContainer.new()
	scol.add_theme_constant_override("separation", 10)
	scol.alignment = BoxContainer.ALIGNMENT_CENTER
	stage.add_child(scol)

	var shown_skin: String = gacha_last["skin"] if not gacha_last.is_empty() else Save.selected_skin
	gacha_preview_holder = CenterContainer.new()
	scol.add_child(gacha_preview_holder)
	var prev := _make_preview("rifle", shown_skin, Vector2(440, 220))
	gacha_preview_holder.add_child(prev)

	gacha_result = _label("喪屍幣足夠就能抽取皮膚！", 26, Color(0.9, 0.85, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
	gacha_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gacha_result.custom_minimum_size = Vector2(460, 70)
	scol.add_child(gacha_result)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 14)
	scol.add_child(btn_row)
	gacha_button = _button("抽獎　（%d 喪屍幣）" % Save.DRAW_COST, _do_draw, Vector2(300, 58), Color(0.75, 0.4, 1.0))
	gacha_button.disabled = not Save.can_draw()
	btn_row.add_child(gacha_button)
	gacha_equip_holder = HBoxContainer.new()
	btn_row.add_child(gacha_equip_holder)

	if not gacha_last.is_empty():
		var rar: Dictionary = WeaponDB.RARITY[WeaponDB.SKINS[gacha_last["skin"]]["rarity"]]
		gacha_result.text = _gacha_text(gacha_last)
		gacha_result.add_theme_color_override("font_color", rar["color"])
		if gacha_last.get("fresh", false):
			gacha_last["fresh"] = false
			prev.modulate = Color(3.0, 3.0, 3.0)
			create_tween().tween_property(prev, "modulate", Color.WHITE, 0.8)
		if not gacha_last["duplicate"] and not gacha_last.get("equipped", false) and Save.selected_skin != gacha_last["skin"]:
			gacha_equip_holder.add_child(_button("立即裝備", _equip_drawn, Vector2(180, 58), GOLD))

	scol.add_child(_label("機率：" + _rarity_chances(), 15, Color(0.7, 0.7, 0.78), HORIZONTAL_ALIGNMENT_CENTER))
	scol.add_child(_label("抽到重複皮膚會返還 %d 枚喪屍幣" % Save.DUPLICATE_REFUND, 15, Color(0.7, 0.7, 0.78), HORIZONTAL_ALIGNMENT_CENTER))

	# 右：收藏
	var coll := _panel(Vector2(0, 0))
	coll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(coll)
	var ccol := VBoxContainer.new()
	ccol.add_theme_constant_override("separation", 8)
	coll.add_child(ccol)
	ccol.add_child(_label("皮膚收藏　%d / %d" % [Save.owned_skins.size(), WeaponDB.SKINS.size()], 24, GOLD))
	for sid in WeaponDB.SKINS:
		var skin: Dictionary = WeaponDB.SKINS[sid]
		var rar2: Dictionary = WeaponDB.RARITY[skin["rarity"]]
		var owned: bool = Save.owned_skins.has(sid)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		ccol.add_child(line)
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(26, 26)
		swatch.color = WeaponDB.skin_color(sid) if owned else Color(0.15, 0.15, 0.18)
		line.add_child(swatch)
		var nm := _label(str(skin["name"]) if owned else "？？？", 20, rar2["color"] if owned else Color(0.45, 0.45, 0.5))
		nm.custom_minimum_size = Vector2(150, 0)
		line.add_child(nm)
		line.add_child(_label("[%s]" % rar2["name"], 16, rar2["color"].darkened(0.1)))


func _equip_drawn() -> void:
	if gacha_last.is_empty():
		return
	Save.selected_skin = gacha_last["skin"]
	Save.save()
	gacha_last["equipped"] = true
	show_page("gacha")


func _do_draw() -> void:
	if busy or not Save.can_draw():
		return
	busy = true
	gacha_button.disabled = true
	for c in gacha_equip_holder.get_children():
		c.queue_free()
	var res := Save.draw_skin()
	if res.is_empty():
		busy = false
		return
	Game.record_max("skins_owned", Save.owned_skins.size())
	Sfx.play("wave", -6.0, 1.5)

	# 滾動動畫
	var ids: Array = WeaponDB.SKINS.keys()
	for i in 16:
		var sid: String = ids[randi() % ids.size()]
		var rar: Dictionary = WeaponDB.RARITY[WeaponDB.SKINS[sid]["rarity"]]
		gacha_result.text = "抽獎中…　" + str(WeaponDB.SKINS[sid]["name"])
		gacha_result.add_theme_color_override("font_color", rar["color"])
		await get_tree().create_timer(0.05 + 0.012 * i).timeout
		if current_page != "gacha":
			return

	res["fresh"] = true
	gacha_last = res
	if not res["duplicate"]:
		Sfx.play("win", -8.0, 1.2)
	show_page("gacha")


# ---------- 排行榜 ----------

func _page_leaderboard() -> void:
	var content := _page_frame("排行榜")
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	content.add_child(tabs)
	tabs.add_child(_button("殭屍關卡榜", _set_lb.bind("zombie"), Vector2(220, 44), Color(0.3, 0.7, 1.0), lb_mode == "zombie"))
	tabs.add_child(_button("大逃殺榜", _set_lb.bind("br"), Vector2(220, 44), Color(1.0, 0.6, 0.25), lb_mode == "br"))

	var panel := _panel(Vector2(0, 0), Color(0.3, 0.55, 0.9, 0.9))
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)

	var is_br := lb_mode == "br"
	var head := _lb_row("名次", "玩家", "勝場" if is_br else "通關", "積分" if is_br else "關卡總分", Color(0.7, 0.8, 1.0), false)
	col.add_child(head)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 400)   # 外層已可捲動，內層需要固定高度
	col.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 4)
	scroll.add_child(rows)

	var my_score := Save.br_best_points if is_br else Save.level_total()
	var my_extra := Save.br_wins if is_br else Save.cleared_level
	var list := Leaderboard.entries(my_score, my_extra, lb_mode)
	var player_row: Control = null
	for i in list.size():
		var e: Dictionary = list[i]
		var color := Color(0.88, 0.88, 0.92)
		match i:
			0:
				color = Color(1.0, 0.84, 0.25)
			1:
				color = Color(0.82, 0.86, 0.92)
			2:
				color = Color(0.9, 0.58, 0.32)
		if e["is_player"]:
			color = Color(0.5, 1.0, 0.6)
		var has_score: bool = not e["is_player"] or e["score"] > 0
		var score_text := str(e["score"]) if has_score else "—"
		var extra_text := str(e["extra"]) if has_score else "—"
		var r := _lb_row("#%d" % (i + 1), str(e["name"]), extra_text, score_text, color, e["is_player"])
		rows.add_child(r)
		if e["is_player"]:
			player_row = r
	col.add_child(_label("排行榜每日更新　·　你的分數：%d" % my_score, 16, Color(0.7, 0.75, 0.85)))

	if player_row != null:
		_scroll_to.call_deferred(scroll, player_row)


func _scroll_to(scroll: ScrollContainer, target: Control) -> void:
	if is_instance_valid(scroll) and is_instance_valid(target):
		scroll.ensure_control_visible(target)


func _lb_row(rank: String, who: String, wave: String, score: String, color: Color, highlight: bool) -> Control:
	var p := PanelContainer.new()
	var bg := Color(0.2, 0.5, 0.3, 0.45) if highlight else Color(1, 1, 1, 0.04)
	p.add_theme_stylebox_override("panel", _box(bg, Color(0.4, 1.0, 0.5, 0.8) if highlight else Color(0, 0, 0, 0), 2 if highlight else 0, 6))
	var h := HBoxContainer.new()
	p.add_child(h)
	var widths := [90, 0, 90, 140]
	var texts := [rank, who, wave, score]
	for i in 4:
		var l := _label(texts[i], 22, color, HORIZONTAL_ALIGNMENT_RIGHT if i >= 2 else HORIZONTAL_ALIGNMENT_LEFT)
		if widths[i] > 0:
			l.custom_minimum_size = Vector2(widths[i], 0)
		else:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
	return p


# ---------- 設定 ----------

func _circle_tex(r: int, color: Color, ring: Color) -> ImageTexture:
	var d := r * 2
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	for y in d:
		for x in d:
			var dist := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			if dist <= r - 1.0:
				img.set_pixel(x, y, color if dist <= r - 4.0 else ring)
			elif dist <= r:
				var c := ring
				c.a = clampf(r - dist, 0.0, 1.0)
				img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


func _style_slider(s: HSlider, accent: Color) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.14, 0.11, 0.12)
	track.set_corner_radius_all(6)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	var fill := StyleBoxFlat.new()
	fill.bg_color = accent
	fill.set_corner_radius_all(6)
	fill.content_margin_top = 5
	fill.content_margin_bottom = 5
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	var gr := 17 if mobile else 11
	s.add_theme_icon_override("grabber", _circle_tex(gr, Color(0.96, 0.9, 0.78), accent))
	s.add_theme_icon_override("grabber_highlight", _circle_tex(gr + 2, Color.WHITE, accent.lightened(0.3)))


func _slider_row(parent: Control, text: String, min_v: float, max_v: float, step: float, value: float, fmt: Callable, on_change: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)
	var l := _label(text, 22)
	l.custom_minimum_size = Vector2(190, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(260 if mobile else 400, 48 if mobile else 30)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_slider(s, ACCENT)
	row.add_child(s)
	var vl := _label(fmt.call(value), 22, GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	vl.custom_minimum_size = Vector2(80, 0)
	row.add_child(vl)
	s.value_changed.connect(func(v: float) -> void:
		vl.text = fmt.call(v)
		on_change.call(v))


func _toggle_row(parent: Control, text: String, value: bool, on_change: Callable, hint: String = "") -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	v.add_child(_label(text, 22))
	if hint != "":
		v.add_child(_label(hint, 15, Color(0.65, 0.65, 0.7)))
	var b := Button.new()
	b.toggle_mode = true
	b.button_pressed = value
	b.custom_minimum_size = Vector2(130, 54) if mobile else Vector2(110, 40)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 22 if mobile else 20)
	var refresh := func() -> void:
		var on := b.button_pressed
		b.text = "開啟" if on else "關閉"
		var c := Color(0.35, 0.75, 0.45) if on else Color(0.5, 0.5, 0.55)
		b.add_theme_color_override("font_color", c.lightened(0.4))
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.add_theme_color_override("font_pressed_color", c.lightened(0.5))
		b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
		for st in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
			b.add_theme_stylebox_override(st, _box(c.darkened(0.7 if st != "hover" else 0.55), c, 2, 20))
	refresh.call()
	b.toggled.connect(func(on: bool) -> void:
		refresh.call()
		on_change.call(on))
	row.add_child(b)


# 單選列：一排互斥按鈕（例如畫質）
func _choice_row(parent: Control, text: String, options: Array, current: int, on_change: Callable, hint: String = "") -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	v.add_child(_label(text, 22))
	if hint != "":
		v.add_child(_label(hint, 15, Color(0.65, 0.65, 0.7)))
	var buttons: Array = []
	for i in options.size():
		var opt: Array = options[i]   # [顯示文字, 值]
		var b := Button.new()
		b.text = str(opt[0])
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(76, 54 if mobile else 40)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.add_theme_font_size_override("font_size", 20)
		buttons.append(b)
		row.add_child(b)
	var refresh := func(sel: int) -> void:
		for i in buttons.size():
			var b: Button = buttons[i]
			var on: bool = int(options[i][1]) == sel
			b.set_pressed_no_signal(on)
			var c := Color(0.35, 0.65, 0.85) if on else Color(0.45, 0.45, 0.5)
			b.add_theme_color_override("font_color", c.lightened(0.45))
			b.add_theme_color_override("font_pressed_color", Color.WHITE)
			b.add_theme_color_override("font_hover_color", Color.WHITE)
			for st in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
				b.add_theme_stylebox_override(st, _box(c.darkened(0.7 if on else 0.8), c, 2, 10))
	refresh.call(current)
	for i in buttons.size():
		var val: int = int(options[i][1])
		(buttons[i] as Button).pressed.connect(func() -> void:
			refresh.call(val)
			on_change.call(val))


func _section(parent: Control, title: String, accent: Color) -> VBoxContainer:
	var p := _panel(Vector2.ZERO, accent.darkened(0.2))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(p)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	p.add_child(col)
	col.add_child(_label(title, 24, accent.lightened(0.3)))
	var rule := ColorRect.new()
	rule.color = Color(accent.r, accent.g, accent.b, 0.5)
	rule.custom_minimum_size = Vector2(0, 2)
	col.add_child(rule)
	return col


func _key_chip(row: Control, key: String, action: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var k := PanelContainer.new()
	k.add_theme_stylebox_override("panel", _box(Color(0.16, 0.13, 0.12), Color(0.45, 0.4, 0.35), 2, 6))
	k.add_child(_label(key, 16, Color(0.98, 0.9, 0.7)))
	h.add_child(k)
	h.add_child(_label(action, 16, Color(0.82, 0.82, 0.88)))
	row.add_child(h)


func _page_settings() -> void:
	var content := _page_frame("設定")
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 20)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(cols)

	# 左欄：音訊與畫面
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 16)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	var snd := _section(left, "音訊與操控", Color(0.8, 0.45, 0.25))
	_slider_row(snd, "主音量", 0.0, 1.0, 0.05, Save.volume,
		func(v: float) -> String: return "%d%%" % int(v * 100.0),
		func(v: float) -> void:
			Save.volume = v
			Save.apply_settings())
	_slider_row(snd, "音樂音量", 0.0, 1.0, 0.05, Save.music_volume,
		func(v: float) -> String: return "關" if v < 0.01 else "%d%%" % int(v * 100.0),
		func(v: float) -> void:
			Save.music_volume = v
			Sfx.apply_music_volume())
	_slider_row(snd, "視角靈敏度" if mobile else "滑鼠靈敏度", 0.2, 3.0, 0.05, Save.sensitivity,
		func(v: float) -> String: return "%.2f" % v,
		func(v: float) -> void: Save.sensitivity = v)

	var vis := _section(left, "畫面", Color(0.35, 0.65, 0.85))
	_slider_row(vis, "視野 (FOV)", 60.0, 110.0, 1.0, Save.fov,
		func(v: float) -> String: return "%d" % int(v),
		func(v: float) -> void: Save.fov = v)
	_slider_row(vis, "動態模糊", 0.0, 1.0, 0.05, Save.motion_blur,
		func(v: float) -> String: return "關" if v < 0.01 else "%d%%" % int(v * 100.0),
		func(v: float) -> void: Save.motion_blur = v)
	_choice_row(vis, "畫質", [["自動", -1], ["低", 0], ["中", 1], ["高", 2]], Save.quality,
		func(v: int) -> void: Save.quality = v,
		"下次開始遊戲生效；低畫質不啟用動態模糊與陰影")
	_toggle_row(vis, "全螢幕", Save.fullscreen, func(on: bool) -> void:
		Save.fullscreen = on
		Save.apply_settings())
	_toggle_row(vis, "觸控操作", Save.touch_mode, func(on: bool) -> void: Save.touch_mode = on,
		"手機 / 平板用；需重新開始遊戲生效")

	if mobile:
		var tch := _section(left, "觸控操作", Color(0.55, 0.8, 0.5))
		_slider_row(tch, "按鍵大小", 0.7, 1.4, 0.05, Save.touch_scale,
			func(v: float) -> String: return "%d%%" % int(v * 100.0),
			func(v: float) -> void: Save.touch_scale = v)
		_slider_row(tch, "按鍵透明度", 0.3, 1.0, 0.05, Save.touch_opacity,
			func(v: float) -> String: return "%d%%" % int(v * 100.0),
			func(v: float) -> void: Save.touch_opacity = v)
		_toggle_row(tch, "左手模式", Save.left_handed, func(on: bool) -> void: Save.left_handed = on,
			"搖桿移到右側、按鍵左右對調")
		tch.add_child(_button("調整按鍵位置", func() -> void: show_page("touch_edit"), Vector2(300, 58), Color(0.55, 0.8, 0.5), false, "wrench"))
		_toggle_row(tch, "陀螺儀瞄準", Save.gyro_aim, func(on: bool) -> void: Save.gyro_aim = on,
			"轉動手機微調準星（需要手機有陀螺儀）")
		_slider_row(tch, "陀螺儀靈敏度", 0.3, 3.0, 0.1, Save.gyro_sens,
			func(v: float) -> String: return "%.1f" % v,
			func(v: float) -> void: Save.gyro_sens = v)
		_toggle_row(tch, "反轉陀螺儀左右", Save.gyro_invert_x, func(on: bool) -> void: Save.gyro_invert_x = on,
			"若轉動方向相反，請切換此項")
		_toggle_row(tch, "反轉陀螺儀上下", Save.gyro_invert_y, func(on: bool) -> void: Save.gyro_invert_y = on)

	# 右欄：操作說明
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 16)
	right.custom_minimum_size = Vector2(380 if mobile else 430, 0)
	cols.add_child(right)
	var help := _section(right, "操作說明", Color(0.82, 0.68, 0.34))
	if mobile:
		var tips := [
			"左下搖桿：移動（推到底往前＝自動奔跑）",
			"右半邊空白處：拖曳轉動視角",
			"右下大鍵 / 左側準星鍵：射擊",
			"跳躍、蹲下、開鏡、換彈、拾取：右側按鈕",
			"大逃殺：點下方武器欄切換槍枝",
			"殭屍關卡：點左上技能列施放技能",
			"左上 ‖ 鍵或手機返回鍵：暫停",
		]
		for tip in tips:
			var tl := _label("・" + tip, 17, Color(0.86, 0.86, 0.9))
			tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			tl.custom_minimum_size = Vector2(330, 0)
			help.add_child(tl)
	else:
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 22)
		grid.add_theme_constant_override("v_separation", 9)
		help.add_child(grid)
		var keys := [
			["WASD", "移動"], ["Ctrl", "奔跑"], ["Shift", "蹲下"], ["空白", "跳躍"],
			["左鍵", "射擊"], ["右鍵", "開鏡"], ["R", "換彈"], ["E", "拾取"],
			["Esc", "暫停"], ["Z–B", "技能（殭屍）"], ["1 2 Q", "切換槍（逃殺）"],
		]
		for k in keys:
			_key_chip(grid, k[0], k[1])

	if not pause_mode:
		var danger := _section(right, "存檔", Color(0.8, 0.25, 0.25))
		var reset_btn: Button = _button("清除所有存檔資料", Callable(), Vector2(300, 46), Color(0.8, 0.2, 0.2))
		reset_btn.pressed.connect(func() -> void:
			if not confirm_reset:
				confirm_reset = true
				reset_btn.text = "再按一次確認清除"
			else:
				confirm_reset = false
				Save.reset_profile()
				Save.apply_settings()
				show_page("settings"))
		danger.add_child(reset_btn)


# ---------- 遊戲大廳 ----------

func _hover_pop(b: Control, scale_to: float = 1.025) -> void:
	b.resized.connect(func() -> void: b.pivot_offset = b.size * 0.5)
	b.mouse_entered.connect(func() -> void:
		b.create_tween().tween_property(b, "scale", Vector2.ONE * scale_to, 0.12).set_trans(Tween.TRANS_QUAD))
	b.mouse_exited.connect(func() -> void:
		b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_QUAD))
	b.focus_entered.connect(func() -> void:
		b.create_tween().tween_property(b, "scale", Vector2.ONE * scale_to, 0.12))
	b.focus_exited.connect(func() -> void:
		b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.12))


func _chip(text: String, color: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := _box(color.darkened(0.6), color.darkened(0.2), 1, 14)
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _label(text, 15, color.lightened(0.45))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	return p


# 大型模式卡片：色條 + 標題 + 英文副標 + 說明 + 戰績標籤
func _mode_card(title: String, tag: String, desc: String, chips: Array, accent: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(540, 190)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var normal := _box(Color(0.05, 0.035, 0.04, 0.9), accent.darkened(0.35), 2, 14)
	normal.shadow_color = Color(0, 0, 0, 0.5)
	normal.shadow_size = 10
	var hover := _box(accent.darkened(0.78), accent.lightened(0.25), 4, 14)
	hover.shadow_color = Color(accent.r, accent.g, accent.b, 0.35)
	hover.shadow_size = 18
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", hover)

	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 22 if side != "left" else 30)
	b.add_child(m)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(h)
	var bar := ColorRect.new()
	bar.color = accent
	bar.custom_minimum_size = Vector2(6, 0)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(bar)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var tl := _label(title, 38, accent.lightened(0.5))
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(tl)
	var tg := _label(tag, 14, accent.lightened(0.1))
	tg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(tg)
	var dl := _label(desc, 17, Color(0.82, 0.82, 0.86))
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(dl)
	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(grow)
	var cr := HBoxContainer.new()
	cr.add_theme_constant_override("separation", 8)
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(cr)
	for c in chips:
		cr.add_child(_chip(str(c), accent))
	var go := _label("出擊 ▶", 24, accent.lightened(0.4))
	go.size_flags_vertical = Control.SIZE_SHRINK_END
	go.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(go)
	b.pressed.connect(cb)
	_hover_pop(b)
	return b


func _page_lobby() -> void:
	var content := _page_frame("遊戲大廳", false)
	# 大廳保留更多背景，減輕遮罩
	for c in page_root.get_children():
		if c is ColorRect:
			(c as ColorRect).color = Color(0.0, 0.0, 0.0, 0.28)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(row)

	# 左：兩種模式
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 18)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var br_best := "第 %d 名" % Save.br_best_place if Save.br_best_place > 0 else "尚無"
	var z_card := _mode_card("殭屍關卡", "ZOMBIE SURVIVAL",
		"10 個關卡，撐過一波波殭屍進攻，學習並突破技能。",
		["通關 %d / %d" % [Save.cleared_level, LevelDB.count()], "總分 %d" % Save.level_total()],
		Color(0.9, 0.35, 0.25), func() -> void:
			sel_level = mini(Save.cleared_level + 1, LevelDB.count())
			show_page("levels"))
	left.add_child(z_card)
	left.add_child(_mode_card("大逃殺", "BATTLE ROYALE",
		"與 11 名 AI 玩家爭奪最後倖存者！槍要在場上撿，奪冠可獲得空投裝備。",
		["勝場 %d" % Save.br_wins, "最佳 %s" % br_best, "擊殺 %d" % Save.br_kills],
		Color(0.95, 0.65, 0.2), func() -> void: show_page("br")))
	z_card.grab_focus.call_deferred()

	# 右：玩家檔案 + 功能
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 12)
	right.custom_minimum_size = Vector2(400, 0)
	row.add_child(right)

	var weapon: Dictionary = WeaponDB.WEAPONS[Save.selected_weapon]
	var skin: Dictionary = WeaponDB.SKINS[Save.selected_skin]
	var prof := _panel(Vector2(400, 0), GOLD.darkened(0.3))
	right.add_child(prof)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 4)
	prof.add_child(pv)
	pv.add_child(_label("目前配置", 20, GOLD))
	var pc := _make_preview(Save.selected_weapon, Save.selected_skin, Vector2(370, 150))
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pv.add_child(pc)
	pv.add_child(_label("%s　·　%s" % [weapon["name"], skin["name"]], 20, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
	var eq := _label("裝備：" + _equip_summary(), 15, Color(0.7, 0.95, 0.75))
	eq.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pv.add_child(eq)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	right.add_child(grid)
	var sz := Vector2(195, 56)
	var gtxt := "皮膚抽獎 !" if Save.can_draw() else "皮膚抽獎"
	var qtxt := "任務 !" if Save.mission_claimable_count() > 0 else "任務"
	grid.add_child(_button("槍枝", func() -> void: show_page("weapons"), sz, GOLD, false, "gun"))
	grid.add_child(_button("裝備", func() -> void: show_page("equipment"), sz, Color(0.4, 0.8, 0.5), false, "shield"))
	grid.add_child(_button(gtxt, func() -> void: show_page("gacha"), sz, Color(0.75, 0.4, 1.0), false, "dice"))
	grid.add_child(_button("排行榜", func() -> void: show_page("leaderboard"), sz, Color(0.3, 0.7, 1.0), false, "trophy"))
	grid.add_child(_button(qtxt, func() -> void:
		quest_tab = "daily"
		show_page("quests"), sz, Color(0.4, 0.85, 0.55), false, "mission"))
	grid.add_child(_button("設定", _open_settings.bind("lobby"), sz, Color(0.6, 0.65, 0.7), false, "gear"))

	# 進場動畫
	page_root.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(page_root, "modulate:a", 1.0, 0.3)


func _equip_summary() -> String:
	var t := Save.equip_totals()
	var parts: PackedStringArray = []
	for k in EquipDB.STAT_NAMES:
		if float(t[k]) > 0.0:
			parts.append("%s+%d%s" % [EquipDB.STAT_NAMES[k], int(t[k]), EquipDB.STAT_UNITS[k]])
	return "　".join(parts) if parts.size() > 0 else "尚未裝備"


# ---------- 關卡選擇 ----------

func _page_levels() -> void:
	var content := _page_frame("殭屍關卡")
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	content.add_child(grid)
	for n in range(1, LevelDB.count() + 1):
		var lv: Dictionary = LevelDB.get_level(n)
		var unlocked := Save.is_level_unlocked(n)
		var theme: Dictionary = lv["theme"]
		var accent: Color = (theme["sky_horizon"] as Color).lightened(0.15)
		var best := int(Save.level_best.get(str(n), 0))
		var txt := "關卡 %d\n%s" % [n, lv["name"]]
		if unlocked:
			txt += "\n%d 波" % lv["waves"]
			if n <= Save.cleared_level:
				txt += "　✔ 通關"
			if best > 0:
				txt += "\n最高 %d" % best
		else:
			txt += "\n[未解鎖]"
		var b := _button(txt, _select_level.bind(n), Vector2(205, 112), accent, n == sel_level)
		b.add_theme_font_size_override("font_size", 18)
		b.disabled = not unlocked
		grid.add_child(b)

	var lv_sel: Dictionary = LevelDB.get_level(sel_level)
	var panel := _panel(Vector2(0, 0), Color(0.9, 0.5, 0.3, 0.9))
	content.add_child(panel)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 24)
	panel.add_child(h)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(info)
	info.add_child(_label("第 %d 關　%s" % [sel_level, lv_sel["name"]], 28, GOLD))
	info.add_child(_label(str(lv_sel["desc"]), 18, Color(0.85, 0.85, 0.9)))
	info.add_child(_label("環境：" + Weather.label_for_level(sel_level), 16, Color(0.6, 0.8, 1.0)))
	var diff := "波數 %d　·　敵人數量 ×%.2f　·　血量 ×%.2f　·　速度 ×%.2f" % [lv_sel["waves"], lv_sel["count_mult"], lv_sel["hp_mult"], lv_sel["speed_mult"]]
	info.add_child(_label(diff, 16, Color(0.8, 0.8, 0.85)))
	info.add_child(_label("首次通關獎勵：%d 喪屍幣" % LevelDB.clear_bonus(sel_level), 16, GOLD))
	var go := _button("▶　出發", func() -> void: Game.begin_run("zombie", sel_level), Vector2(220, 64), GOLD)
	go.disabled = not Save.is_level_unlocked(sel_level)
	h.add_child(go)
	if mobile:
		content.move_child(panel, 0)


# ---------- 大逃殺介紹 ----------

func _page_br() -> void:
	var content := _page_frame("大逃殺")
	var panel := _panel(Vector2(0, 0), Color(0.95, 0.65, 0.2, 0.9))
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(panel)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 30)
	panel.add_child(h)

	var rules := VBoxContainer.new()
	rules.add_theme_constant_override("separation", 8)
	rules.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(rules)
	rules.add_child(_label("規則", 26, GOLD))
	var lines := [
		"・共 12 名玩家：你 + 11 名 AI 玩家，活到最後就是第一名",
		"・開局從高空跳傘（跳躍鍵開傘），落地後再撿槍；你和 AI 都是徒手開局",
		("・槍枝要在地圖上撿取（點「拾取」鈕，可帶 2 把，點下方武器欄切換）" if mobile else "・槍枝要在地圖上撿取（E 拾取，可帶 2 把，1 / 2 / Q 切換）"),
		("・手榴彈、醫療包、護甲板在右下按鈕使用；被攻擊會打斷治療" if mobile else "・G 丟手榴彈　H 醫療包（3 秒，受傷會中斷）　T 護甲板（+25 護盾）"),
		"・約 50 秒與 125 秒會空投補給箱（小地圖橘色標記），裡面有好槍和道具，AI 也會搶",
		"・你的裝備（頭盔、護甲…）是場外裝，會帶進比賽",
		"・安全區會逐步縮小，圈外持續受傷；小地圖可查看安全區",
		("・蹲下（更穩、更難被發現）；搖桿推到底往前自動奔跑" if mobile else "・Shift 蹲下（更穩、更難被發現）　Ctrl 奔跑"),
		"・本模式沒有技能；每擊殺一名玩家獲得 1 喪屍幣，名次越高獎勵越多",
		"・奪得第一名會有空投降落，打開可獲得裝備（含傳說級空投限定裝備）！",
	]
	for line in lines:
		var l := _label(line, 18, Color(0.88, 0.88, 0.92))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(560, 0)
		rules.add_child(l)

	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 10)
	h.add_child(side)
	side.add_child(_label("你的戰績", 24, GOLD))
	side.add_child(_label("場次 %d　勝場 %d\n累計擊殺 %d\n最佳名次 %s\n最高積分 %d" % [Save.br_games, Save.br_wins, Save.br_kills, ("第 %d 名" % Save.br_best_place) if Save.br_best_place > 0 else "—", Save.br_best_points], 20, Color(0.88, 0.88, 0.92)))
	side.add_child(_label("目前裝備加成\n" + _equip_summary(), 17, Color(0.7, 0.95, 0.75)))
	side.add_child(_button("▶　開始大逃殺", func() -> void: Game.begin_run("br", 1), Vector2(300, 64), GOLD))


# ---------- 裝備 ----------

func _page_equipment() -> void:
	var content := _page_frame("裝備")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(row)

	# 左：部位
	var lp := _panel(Vector2(300, 0))
	row.add_child(lp)
	var lcol := VBoxContainer.new()
	lcol.add_theme_constant_override("separation", 8)
	lp.add_child(lcol)
	for slot in EquipDB.SLOTS:
		var cur: String = Save.equipped.get(slot, "")
		var txt := "%s　%s" % [EquipDB.SLOT_NAMES[slot], EquipDB.item_name(cur) if cur != "" else "（空）"]
		var accent: Color = EquipDB.tier_info(cur)["color"] if cur != "" else Color(0.5, 0.5, 0.55)
		var b := _button(txt, _select_eq_slot.bind(slot), Vector2(270, 46), accent, slot == eq_slot)
		b.add_theme_font_size_override("font_size", 18)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		lcol.add_child(b)

	# 右：該部位的 4 階裝備
	var rp := _panel(Vector2(0, 0))
	rp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(rp)
	var rcol := VBoxContainer.new()
	rcol.add_theme_constant_override("separation", 10)
	rp.add_child(rcol)
	rcol.add_child(_label("%s（用喪屍幣購買，傳說級為大逃殺空投限定）" % EquipDB.SLOT_NAMES[eq_slot], 20, GOLD))
	for t in range(1, 5):
		var id := EquipDB.item_id(eq_slot, t)
		var info: Dictionary = EquipDB.tier_info(id)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		rcol.add_child(line)
		var nm := _label("【%s】%s" % [info["name"], EquipDB.item_name(id)], 20, info["color"] if Save.owned_equip.has(id) or not EquipDB.airdrop_only(id) else info["color"])
		nm.custom_minimum_size = Vector2(250, 0)
		line.add_child(nm)
		var st := _label(EquipDB.stats_text(id), 17, Color(0.8, 0.95, 0.8))
		st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(st)
		var owned := Save.owned_equip.has(id)
		var btn: Button
		if owned and str(Save.equipped.get(eq_slot, "")) == id:
			btn = _button("卸下", _eq_unequip, Vector2(150, 42), Color(0.6, 0.6, 0.65), true)
		elif owned:
			btn = _button("裝備", _eq_equip.bind(id), Vector2(150, 42), Color(0.4, 0.8, 0.5))
		elif EquipDB.airdrop_only(id):
			btn = _button("空投限定", Callable(), Vector2(150, 42), Color(1.0, 0.75, 0.2))
			btn.disabled = true
		else:
			btn = _button("購買 %d" % EquipDB.cost(id), _eq_buy.bind(id), Vector2(150, 42), GOLD)
			btn.disabled = Save.coins < EquipDB.cost(id)
		btn.add_theme_font_size_override("font_size", 18)
		line.add_child(btn)

	rcol.add_child(HSeparator.new())
	rcol.add_child(_label("目前總加成", 20, GOLD))
	var totals := Save.equip_totals()
	var tg := GridContainer.new()
	tg.columns = 3
	tg.add_theme_constant_override("h_separation", 30)
	rcol.add_child(tg)
	for k in EquipDB.STAT_NAMES:
		var v := int(totals[k])
		tg.add_child(_label("%s　+%d%s" % [EquipDB.STAT_NAMES[k], v, EquipDB.STAT_UNITS[k]], 18, Color(0.85, 0.95, 0.85) if v > 0 else Color(0.5, 0.5, 0.55)))



# ---------- 手機版面 ----------

# 手機頁面外框的邊距（含安全區）
func _mobile_margin(extra: float = 14.0) -> MarginContainer:
	var ins := UIUtil.safe_insets(self)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", int(ins.x + extra))
	m.add_theme_constant_override("margin_top", int(ins.y + extra * 0.6))
	m.add_theme_constant_override("margin_right", int(ins.z + extra))
	m.add_theme_constant_override("margin_bottom", int(ins.w + extra * 0.6))
	return m


func _mobile_frame(title: String) -> VBoxContainer:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.02, 0.78) if pause_mode else Color(0.0, 0.0, 0.0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_root.add_child(dim)
	var margin := _mobile_margin()
	page_root.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	root.add_child(header)
	header.add_child(_button("◀", _back, Vector2(84, 62), ACCENT))
	var tl := _label(title, 38, Color(0.98, 0.85, 0.6))
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(tl)
	if not pause_mode:
		header.add_child(_coin_panel())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)
	return content


func _page_main_mobile() -> void:
	var margin := _mobile_margin(28.0)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_root.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)

	# 左：標題與戰績
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	col.add_child(_label("SURVIVE　·　FIGHT　·　EVOLVE", 16, Color(0.9, 0.6, 0.5, 0.9)))
	var title_box := Control.new()
	title_box.custom_minimum_size = Vector2(440, 100)
	title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(title_box)
	var shadow := _label("廢棄城市", 84, Color(0.55, 0.02, 0.02))
	shadow.position = Vector2(4, 5)
	title_box.add_child(shadow)
	title_label = _label("廢棄城市", 84, Color(0.82, 0.74, 0.6))
	title_label.add_theme_constant_override("outline_size", 11)
	title_label.add_theme_color_override("font_outline_color", Color(0.45, 0.04, 0.02))
	title_box.add_child(title_label)
	col.add_child(_label("ABANDONED CITY　FPS", 24, Color(0.95, 0.5, 0.35)))
	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(grow)

	var weapon: Dictionary = WeaponDB.WEAPONS[Save.selected_weapon]
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(chips)
	chips.add_child(_chip("槍：%s" % weapon["name"], GOLD))
	chips.add_child(_chip("通關 %d / %d" % [Save.cleared_level, LevelDB.count()], Color(0.9, 0.35, 0.25)))
	chips.add_child(_chip("逃殺勝場 %d" % Save.br_wins, Color(0.95, 0.65, 0.2)))
	var chips2 := HBoxContainer.new()
	chips2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(chips2)
	chips2.add_child(_chip("累計擊殺 %d" % (Save.total_kills + Save.br_kills), Color(0.5, 0.7, 0.9)))

	# 右：大按鈕
	var btns := VBoxContainer.new()
	btns.add_theme_constant_override("separation", 12)
	btns.custom_minimum_size = Vector2(380, 0)
	btns.alignment = BoxContainer.ALIGNMENT_END
	btns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(btns)
	var coin := _coin_panel()
	coin.size_flags_horizontal = Control.SIZE_SHRINK_END
	btns.add_child(coin)
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btns.add_child(gap)
	var first := _button("開始遊戲", func() -> void: show_page("lobby"), Vector2(380, 96), GOLD, true, "play")
	first.add_theme_font_size_override("font_size", 32)
	btns.add_child(first)
	btns.add_child(_button("設定", _open_settings.bind("main"), Vector2(380, 66), Color(0.6, 0.65, 0.7), false, "gear"))
	# 呼吸動畫
	first.resized.connect(func() -> void: first.pivot_offset = first.size * 0.5)
	var tw := first.create_tween().set_loops()
	tw.tween_property(first, "scale", Vector2(1.03, 1.03), 0.9).set_trans(Tween.TRANS_SINE)
	tw.tween_property(first, "scale", Vector2.ONE, 0.9).set_trans(Tween.TRANS_SINE)


# 手機大廳用模式卡：直式排列，整張卡片可點
func _mode_card_mobile(title: String, tag: String, desc: String, chips: Array, accent: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(300, 0)
	var normal := _box(Color(0.05, 0.035, 0.04, 0.92), accent.darkened(0.2), 3, 18)
	normal.border_width_top = 8
	normal.shadow_color = Color(0, 0, 0, 0.5)
	normal.shadow_size = 10
	var hover := _box(accent.darkened(0.72), accent.lightened(0.25), 4, 18)
	hover.border_width_top = 8
	for st in ["pressed", "hover", "focus"]:
		b.add_theme_stylebox_override(st, hover)
	b.add_theme_stylebox_override("normal", normal)

	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 18)
	m.add_theme_constant_override("margin_top", 22)
	b.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(v)
	var tl := _label(title, 42, accent.lightened(0.5))
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(tl)
	var tg := _label(tag, 15, accent.lightened(0.1))
	tg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(tg)
	var dl := _label(desc, 18, Color(0.84, 0.84, 0.88))
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(dl)
	var art_box := Control.new()
	art_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art_box.custom_minimum_size = Vector2(0, 60)
	art_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_box.draw.connect(_draw_mode_art.bind(art_box, title, accent))
	v.add_child(art_box)
	var cr := HFlowContainer.new()
	cr.add_theme_constant_override("h_separation", 6)
	cr.add_theme_constant_override("v_separation", 6)
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(cr)
	for c in chips:
		cr.add_child(_chip(str(c), accent))
	var go := PanelContainer.new()
	var gsb := _box(accent.darkened(0.25), accent.lightened(0.1), 2, 12)
	gsb.content_margin_top = 10
	gsb.content_margin_bottom = 10
	go.add_theme_stylebox_override("panel", gsb)
	go.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gl := _label("出擊 ▶", 26, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	gl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	go.add_child(gl)
	v.add_child(go)
	b.pressed.connect(cb)
	return b


# 模式卡中央的簡易插畫：殭屍 = 紅色警戒光暈與剪影；大逃殺 = 縮圈與準星
func _draw_mode_art(c: Control, title: String, accent: Color) -> void:
	var sz := c.size
	var ctr := sz * 0.5
	var r := minf(sz.x * 0.45, sz.y * 0.48)
	if r < 10.0:
		return
	for i in 6:
		c.draw_circle(ctr, r * (1.0 - float(i) * 0.14), Color(accent.r, accent.g, accent.b, 0.05 + 0.02 * i))
	if title == "大逃殺":
		c.draw_arc(ctr, r, 0.0, TAU, 48, Color(accent.r, accent.g, accent.b, 0.9), 3.0)
		c.draw_arc(ctr, r * 0.62, 0.0, TAU, 40, Color(1, 1, 1, 0.5), 2.0)
		for k in 4:
			var d := Vector2.from_angle(float(k) * PI * 0.5 + 0.4)
			c.draw_line(ctr + d * r * 0.25, ctr + d * r * 0.5, Color(1, 1, 1, 0.8), 3.0)
		c.draw_circle(ctr, 4.0, Color(1, 0.3, 0.2))
	else:
		var col := Color(0.02, 0.01, 0.02, 0.95)
		var sc := r / 60.0
		var hip := ctr + Vector2(0, r * 0.75)
		var sh := hip + Vector2(6, -r * 1.0) * 1.0
		c.draw_line(hip + Vector2(-8, 0) * sc, hip + Vector2(-12, 34) * sc * 0.6, col, 12.0 * sc)
		c.draw_line(hip + Vector2(8, 0) * sc, hip + Vector2(14, 34) * sc * 0.6, col, 12.0 * sc)
		c.draw_line(hip, sh, col, 30.0 * sc)
		c.draw_line(sh, sh + Vector2(-48, -10) * sc, col, 9.0 * sc)
		c.draw_line(sh, sh + Vector2(-42, 0) * sc, col, 9.0 * sc)
		var head := sh + Vector2(4, -22) * sc
		c.draw_circle(head, 14.0 * sc, col)
		c.draw_circle(head + Vector2(-5, -1) * sc, 2.4 * sc + 0.5, Color(1, 0.1, 0.1))
		c.draw_circle(head + Vector2(3, -1) * sc, 2.4 * sc + 0.5, Color(1, 0.1, 0.1))


func _page_lobby_mobile() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.3)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_root.add_child(dim)
	var margin := _mobile_margin()
	page_root.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	# 頂列
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	root.add_child(header)
	header.add_child(_button("◀", _back, Vector2(84, 62), ACCENT))
	var tl := _label("遊戲大廳", 38, Color(0.98, 0.85, 0.6))
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(tl)
	header.add_child(_coin_panel())
	header.add_child(_button("設定", _open_settings.bind("lobby"), Vector2(150, 62), Color(0.6, 0.65, 0.7), false, "gear"))

	# 中段：玩家卡 + 兩個模式
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	var weapon: Dictionary = WeaponDB.WEAPONS[Save.selected_weapon]
	var skin: Dictionary = WeaponDB.SKINS[Save.selected_skin]
	var prof := _panel(Vector2(320, 0), GOLD.darkened(0.3))
	body.add_child(prof)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 4)
	prof.add_child(pv)
	pv.add_child(_label("目前配置", 20, GOLD))
	var pc := _make_preview(Save.selected_weapon, Save.selected_skin, Vector2(290, 170))
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pv.add_child(pc)
	pv.add_child(_label("%s" % weapon["name"], 24, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
	pv.add_child(_label("皮膚：%s" % skin["name"], 16, Color(0.8, 0.8, 0.86), HORIZONTAL_ALIGNMENT_CENTER))
	var dmg_total: float = float(weapon["damage"]) * float(weapon["pellets"])
	_stat_row(pv, "傷害", dmg_total / 160.0 * 100.0, Color(1.0, 0.4, 0.3))
	_stat_row(pv, "射速", 1.0 / float(weapon["fire_rate"]) / 16.0 * 100.0, Color(1.0, 0.8, 0.3))
	_stat_row(pv, "射程", float(weapon["range"]) / 300.0 * 100.0, Color(0.4, 0.75, 1.0))
	var eq := _label("裝備：" + _equip_summary(), 15, Color(0.7, 0.95, 0.75))
	eq.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pv.add_child(eq)

	var br_best := "第 %d 名" % Save.br_best_place if Save.br_best_place > 0 else "尚無"
	var z_card := _mode_card_mobile("殭屍關卡", "ZOMBIE SURVIVAL",
		"10 個關卡，撐過一波波殭屍進攻，學習並突破技能。",
		["通關 %d / %d" % [Save.cleared_level, LevelDB.count()], "總分 %d" % Save.level_total()],
		Color(0.9, 0.35, 0.25), func() -> void:
			sel_level = mini(Save.cleared_level + 1, LevelDB.count())
			show_page("levels"))
	body.add_child(z_card)
	body.add_child(_mode_card_mobile("大逃殺", "BATTLE ROYALE",
		"與 11 名 AI 玩家爭奪最後倖存者！槍要在場上撿，奪冠可獲得空投裝備。",
		["勝場 %d" % Save.br_wins, "最佳 %s" % br_best, "擊殺 %d" % Save.br_kills],
		Color(0.95, 0.65, 0.2), func() -> void: show_page("br")))

	# 底部導覽列
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 10)
	root.add_child(nav)
	var nsz := Vector2(0, 66)
	var gtxt := "抽獎 !" if Save.can_draw() else "抽獎"
	var qtxt := "任務 !" if Save.mission_claimable_count() > 0 else "任務"
	var navs := [
		["槍枝", "weapons", Color(0.82, 0.68, 0.34), "gun"],
		["裝備", "equipment", Color(0.4, 0.8, 0.5), "shield"],
		[gtxt, "gacha", Color(0.75, 0.4, 1.0), "dice"],
		["排行榜", "leaderboard", Color(0.3, 0.7, 1.0), "trophy"],
		[qtxt, "quests", Color(0.4, 0.85, 0.55), "mission"],
	]
	for n in navs:
		var page: String = n[1]
		var nb := _button(n[0], func() -> void:
			quest_tab = "daily"
			show_page(page), nsz, n[2], false, n[3])
		nb.add_theme_font_size_override("font_size", 23)
		nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nav.add_child(nb)

	page_root.modulate.a = 0.0
	create_tween().tween_property(page_root, "modulate:a", 1.0, 0.3)



# ---------- 任務與成就 ----------

var quest_tab: String = "daily"


func _quest_bar(value: float, max_value: float, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = maxf(max_value, 1.0)
	bar.value = clampf(value, 0.0, max_value)
	bar.custom_minimum_size = Vector2(0, 14)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(6)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0.6)
	back.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", back)
	return bar


func _page_quests() -> void:
	var content := _page_frame("任務與成就")
	Save.ensure_missions()
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	content.add_child(tabs)
	var n_claim := Save.mission_claimable_count()
	tabs.add_child(_button("每日任務" + (" !" if n_claim > 0 else ""), func() -> void:
		quest_tab = "daily"
		show_page("quests"), Vector2(220, 46), Color(0.4, 0.85, 0.55), quest_tab == "daily", "mission"))
	tabs.add_child(_button("成就　%d / %d" % [Save.achievements.size(), ProgressDB.ACHIEVEMENTS.size()], func() -> void:
		quest_tab = "ach"
		show_page("quests"), Vector2(220, 46), Color(1.0, 0.8, 0.3), quest_tab == "ach", "star"))

	if quest_tab == "daily":
		var hint := _label("每天 0:00 重置　·　完成後點「領取」獲得喪屍幣與經驗值", 17, Color(0.75, 0.75, 0.82))
		content.add_child(hint)
		var list: Array = Save.missions["list"]
		for i in list.size():
			var m: Dictionary = list[i]
			var done := int(m["progress"]) >= int(m["target"])
			var claimed := bool(m["claimed"])
			var border := Color(0.4, 0.85, 0.55) if done else Color(0.45, 0.45, 0.55)
			var card := _panel(Vector2(0, 0), border)
			content.add_child(card)
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 18)
			card.add_child(h)
			var v := VBoxContainer.new()
			v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			v.add_theme_constant_override("separation", 6)
			h.add_child(v)
			v.add_child(_label(str(m["text"]), 24, Color.WHITE if not claimed else Color(0.6, 0.6, 0.65)))
			var br := HBoxContainer.new()
			br.add_theme_constant_override("separation", 12)
			v.add_child(br)
			br.add_child(_quest_bar(float(m["progress"]), float(m["target"]), Color(0.4, 0.85, 0.55)))
			var pl := _label("%d / %d" % [int(m["progress"]), int(m["target"])], 18, Color(0.85, 0.9, 0.85))
			pl.custom_minimum_size = Vector2(90, 0)
			br.add_child(pl)
			var chips := HBoxContainer.new()
			chips.add_theme_constant_override("separation", 8)
			v.add_child(chips)
			chips.add_child(_chip("+%d 喪屍幣" % int(m["coins"]), GOLD))
			chips.add_child(_chip("+%d 經驗" % int(m["xp"]), Color(0.5, 0.75, 1.0)))
			var btn: Button
			if claimed:
				btn = _button("已領取", Callable(), Vector2(170, 56), Color(0.5, 0.5, 0.55), false, "check")
				btn.disabled = true
			elif done:
				var idx := i
				btn = _button("領取", func() -> void:
					if Game.claim_mission(idx):
						Sfx.play("pickup", 0.0, 1.4)
					show_page("quests"), Vector2(170, 56), GOLD, true, "coin")
			else:
				btn = _button("進行中", Callable(), Vector2(170, 56), Color(0.45, 0.45, 0.55))
				btn.disabled = true
			btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(btn)
	else:
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 12)
		content.add_child(grid)
		for a in ProgressDB.ACHIEVEMENTS:
			var unlocked := Save.achievements.has(a["id"])
			var cur := int(Save.stats.get(a["stat"], 0))
			var card := _panel(Vector2(0, 0), Color(1.0, 0.8, 0.3) if unlocked else Color(0.4, 0.4, 0.5))
			card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(card)
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 12)
			card.add_child(h)
			var ic := IconRect.make("check" if unlocked else "star", Color(1.0, 0.85, 0.35) if unlocked else Color(0.45, 0.45, 0.52), 38)
			ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(ic)
			var v := VBoxContainer.new()
			v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			v.add_theme_constant_override("separation", 3)
			h.add_child(v)
			v.add_child(_label(str(a["name"]), 21, Color(1.0, 0.88, 0.5) if unlocked else Color.WHITE))
			var dl := _label(str(a["desc"]), 15, Color(0.78, 0.78, 0.84))
			dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_child(dl)
			var br := HBoxContainer.new()
			v.add_child(br)
			br.add_child(_quest_bar(float(cur), float(a["target"]), Color(1.0, 0.8, 0.3) if unlocked else Color(0.45, 0.6, 0.85)))
			var pl := _label("%d / %d" % [mini(cur, int(a["target"])), int(a["target"])], 15, Color(0.85, 0.85, 0.9), HORIZONTAL_ALIGNMENT_RIGHT)
			pl.custom_minimum_size = Vector2(80, 0)
			br.add_child(pl)
			v.add_child(_label("獎勵 +%d 喪屍幣%s" % [int(a["coins"]), ("　+%d 經驗" % int(a["xp"])) if int(a["xp"]) > 0 else ""], 14, GOLD.darkened(0.1)))



# ---------- 觸控按鍵位置編輯 ----------

func _page_touch_edit() -> void:
	var editor := TouchEditor.new()
	page_root.add_child(editor)
	var ins := UIUtil.safe_insets(self)
	var panel := _panel(Vector2.ZERO, Color(0.4, 0.7, 0.9, 0.9))
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.offset_top = ins.y + 10.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	page_root.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	col.add_child(_label("拖曳圓形按鍵調整位置（所見即所得）", 20, Color(0.85, 0.92, 1.0), HORIZONTAL_ALIGNMENT_CENTER))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	col.add_child(row)
	var sc := _compact_slider("大小", 0.7, 1.4, 0.05, Save.touch_scale, func(v: float) -> void:
		Save.touch_scale = v
		editor.queue_redraw())
	row.add_child(sc)
	var op := _compact_slider("透明度", 0.3, 1.0, 0.05, Save.touch_opacity, func(v: float) -> void:
		Save.touch_opacity = v
		editor.queue_redraw())
	row.add_child(op)
	var lh := Button.new()
	lh.toggle_mode = true
	lh.button_pressed = Save.left_handed
	lh.text = "左手模式：" + ("開" if Save.left_handed else "關")
	lh.custom_minimum_size = Vector2(170, 48)
	lh.add_theme_font_size_override("font_size", 19)
	lh.toggled.connect(func(on: bool) -> void:
		Save.left_handed = on
		lh.text = "左手模式：" + ("開" if on else "關")
		editor.queue_redraw())
	row.add_child(lh)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 14)
	brow.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(brow)
	brow.add_child(_button("重設位置", func() -> void:
		Save.touch_layout = {}
		Save.touch_scale = 1.0
		Save.touch_opacity = 0.85
		Save.left_handed = false
		Save.save()
		show_page("touch_edit"), Vector2(180, 52), Color(0.8, 0.45, 0.3)))
	brow.add_child(_button("完成", _back, Vector2(180, 52), GOLD, true, "check"))


# 精簡的標題 + 滑桿（編輯器面板用）
func _compact_slider(text: String, min_v: float, max_v: float, step: float, value: float, on_change: Callable) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.add_child(_label(text, 19))
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(150, 40)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_slider(s, Color(0.4, 0.7, 0.9))
	h.add_child(s)
	var vl := _label("%d%%" % int(value * 100.0), 19, GOLD)
	vl.custom_minimum_size = Vector2(56, 0)
	h.add_child(vl)
	s.value_changed.connect(func(v: float) -> void:
		vl.text = "%d%%" % int(v * 100.0)
		on_change.call(v))
	return h


# ---------- 按鈕回呼 ----------

func _open_settings(ret: String) -> void:
	settings_return = ret
	show_page("settings")


func _select_level(n: int) -> void:
	sel_level = n
	show_page("levels")


func _set_lb(mode: String) -> void:
	lb_mode = mode
	show_page("leaderboard")


func _select_eq_slot(slot: String) -> void:
	eq_slot = slot
	show_page("equipment")


func _eq_unequip() -> void:
	Save.unequip_slot(eq_slot)
	show_page("equipment")


func _eq_equip(id: String) -> void:
	Save.equip_item(id)
	show_page("equipment")


func _eq_buy(id: String) -> void:
	if Save.buy_equip(id):
		Sfx.play("pickup")
	show_page("equipment")
