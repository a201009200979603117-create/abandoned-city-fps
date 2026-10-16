extends Control
# 主選單：封面、槍枝選擇、抽獎、排行榜、設定。全部以程式建立。

const WeaponDB = preload("res://scripts/data/weapon_db.gd")
const Leaderboard = preload("res://scripts/data/leaderboard.gd")
const CoverArt = preload("res://ui/cover_art.gd")
const EquipDB = preload("res://scripts/data/equip_db.gd")
const LevelDB = preload("res://scripts/data/level_db.gd")

const PAGE_PARENT: Dictionary = {
	"lobby": "main", "weapons": "lobby", "gacha": "lobby", "leaderboard": "lobby",
	"levels": "lobby", "br": "lobby", "equipment": "lobby",
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
		coin_label.text = "◉ 喪屍幣　%d" % Save.coins
	if is_instance_valid(title_label):
		# 偶爾閃爍的霓虹招牌
		var flick := 1.0 if sin(t * 17.0) * sin(t * 5.3) > -0.93 else 0.55
		title_label.modulate.a = flick


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


func _button(text: String, cb: Callable, min_size: Vector2 = Vector2(300, 52), accent: Color = ACCENT, selected: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", 22)
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
	if not cb.is_null():
		b.pressed.connect(cb)
	return b


func _clear_page() -> void:
	coin_label = null
	title_label = null
	preview_pivot = null
	for c in page_root.get_children():
		c.queue_free()


func _coin_panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(Color(0.06, 0.05, 0.03, 0.9), GOLD.darkened(0.2), 2, 20))
	coin_label = _label("◉ 喪屍幣　%d" % Save.coins, 24, GOLD)
	p.add_child(coin_label)
	return p


# 子頁面骨架：標題列（含喪屍幣）+ 內容 + 返回鈕。回傳內容容器
func _page_frame(title: String) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	page_root.add_child(margin)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
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
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
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
	_clear_page()
	match page:
		"main":
			_page_main()
		"lobby":
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

	var first := _button("▶　開始遊戲", func() -> void: show_page("lobby"), Vector2(330, 58), GOLD)
	col.add_child(first)
	col.add_child(_button("設定", _open_settings.bind("main"), Vector2(330, 48), Color(0.6, 0.65, 0.7)))
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
	vp.msaa_3d = Viewport.MSAA_2X
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

func _slider_row(parent: Control, text: String, min_v: float, max_v: float, step: float, value: float, fmt: Callable, on_change: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)
	var l := _label(text, 22)
	l.custom_minimum_size = Vector2(170, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(380, 30)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(s)
	var vl := _label(fmt.call(value), 22, GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	vl.custom_minimum_size = Vector2(90, 0)
	row.add_child(vl)
	s.value_changed.connect(func(v: float) -> void:
		vl.text = fmt.call(v)
		on_change.call(v))


func _page_settings() -> void:
	var content := _page_frame("設定")
	var panel := _panel(Vector2(0, 0), Color(0.5, 0.55, 0.6, 0.9))
	content.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	panel.add_child(col)

	_slider_row(col, "主音量", 0.0, 1.0, 0.05, Save.volume,
		func(v: float) -> String: return "%d%%" % int(v * 100.0),
		func(v: float) -> void:
			Save.volume = v
			Save.apply_settings())
	_slider_row(col, "滑鼠靈敏度", 0.2, 3.0, 0.05, Save.sensitivity,
		func(v: float) -> String: return "%.2f" % v,
		func(v: float) -> void: Save.sensitivity = v)
	_slider_row(col, "視野 (FOV)", 60.0, 110.0, 1.0, Save.fov,
		func(v: float) -> String: return "%d" % int(v),
		func(v: float) -> void: Save.fov = v)

	var fs := CheckButton.new()
	fs.text = "全螢幕"
	fs.add_theme_font_size_override("font_size", 22)
	fs.button_pressed = Save.fullscreen
	fs.toggled.connect(func(on: bool) -> void:
		Save.fullscreen = on
		Save.apply_settings())
	col.add_child(fs)

	var tm := CheckButton.new()
	tm.text = "觸控操作（手機/平板；需重新開始遊戲生效）"
	tm.add_theme_font_size_override("font_size", 22)
	tm.button_pressed = Save.touch_mode
	tm.toggled.connect(func(on: bool) -> void: Save.touch_mode = on)
	col.add_child(tm)

	col.add_child(HSeparator.new())
	col.add_child(_label("操作說明", 22, Color(0.95, 0.85, 0.6)))
	col.add_child(_label("WASD 移動　Ctrl 奔跑　Shift 蹲下　空白鍵 跳躍　滑鼠 瞄準　左鍵 射擊　右鍵 開鏡(狙擊槍)\nR 換彈　E 拾取　Esc 暫停　Z X C V B 施放技能（殭屍關卡）　1 / 2 / Q 切換槍（大逃殺）", 18, Color(0.85, 0.85, 0.9)))

	if not pause_mode:
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
		col.add_child(reset_btn)


# ---------- 遊戲大廳 ----------

func _mode_card(text: String, accent: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(430, 150)
	b.add_theme_font_size_override("font_size", 21)
	b.add_theme_color_override("font_color", Color.WHITE)
	var normal := _box(accent.darkened(0.7), accent, 3, 12)
	normal.content_margin_left = 20
	normal.content_margin_right = 20
	var hover := _box(accent.darkened(0.5), accent.lightened(0.3), 4, 12)
	hover.content_margin_left = 20
	hover.content_margin_right = 20
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", hover)
	b.pressed.connect(cb)
	return b


func _page_lobby() -> void:
	var content := _page_frame("遊戲大廳")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(row)

	# 左：兩種模式
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 14)
	row.add_child(left)
	left.add_child(_label("選擇模式", 24, Color(0.95, 0.85, 0.6)))
	var z_card := _mode_card("殭屍關卡\n10 個關卡，撐過一波波殭屍進攻，學習並突破技能。\n已通關 %d / %d 關　·　關卡總分 %d" % [Save.cleared_level, LevelDB.count(), Save.level_total()],
		Color(0.9, 0.35, 0.25), func() -> void:
			sel_level = mini(Save.cleared_level + 1, LevelDB.count())
			show_page("levels"))
	left.add_child(z_card)
	var br_best := "第 %d 名" % Save.br_best_place if Save.br_best_place > 0 else "尚無"
	left.add_child(_mode_card("大逃殺\n與 11 名 AI 玩家爭奪最後倖存者！槍要在場上撿，奪冠可獲得空投裝備。\n勝場 %d　·　最佳名次 %s" % [Save.br_wins, br_best],
		Color(0.95, 0.65, 0.2), func() -> void: show_page("br")))
	z_card.grab_focus.call_deferred()

	# 右：功能
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	row.add_child(right)
	right.add_child(_label("準備", 24, Color(0.95, 0.85, 0.6)))
	right.add_child(_button("槍枝選擇", func() -> void: show_page("weapons"), Vector2(300, 50)))
	right.add_child(_button("裝備", func() -> void: show_page("equipment"), Vector2(300, 50), Color(0.4, 0.8, 0.5)))
	var gtxt := "皮膚抽獎　(可抽獎!)" if Save.can_draw() else "皮膚抽獎"
	right.add_child(_button(gtxt, func() -> void: show_page("gacha"), Vector2(300, 50), Color(0.75, 0.4, 1.0)))
	right.add_child(_button("排行榜", func() -> void: show_page("leaderboard"), Vector2(300, 50), Color(0.3, 0.7, 1.0)))
	right.add_child(_button("設定", _open_settings.bind("lobby"), Vector2(300, 50), Color(0.6, 0.65, 0.7)))

	var weapon: Dictionary = WeaponDB.WEAPONS[Save.selected_weapon]
	var skin: Dictionary = WeaponDB.SKINS[Save.selected_skin]
	var sum := _panel(Vector2(300, 0))
	right.add_child(sum)
	var sc := VBoxContainer.new()
	sum.add_child(sc)
	sc.add_child(_label("目前配置", 18, GOLD))
	sc.add_child(_label("槍：%s\n皮膚：%s" % [weapon["name"], skin["name"]], 16, Color(0.85, 0.85, 0.9)))
	sc.add_child(_label("裝備：" + _equip_summary(), 16, Color(0.7, 0.95, 0.75)))


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
	var diff := "波數 %d　·　敵人數量 ×%.2f　·　血量 ×%.2f　·　速度 ×%.2f" % [lv_sel["waves"], lv_sel["count_mult"], lv_sel["hp_mult"], lv_sel["speed_mult"]]
	info.add_child(_label(diff, 16, Color(0.8, 0.8, 0.85)))
	info.add_child(_label("首次通關獎勵：%d 喪屍幣" % LevelDB.clear_bonus(sel_level), 16, GOLD))
	var go := _button("▶　出發", func() -> void: Game.begin_run("zombie", sel_level), Vector2(220, 64), GOLD)
	go.disabled = not Save.is_level_unlocked(sel_level)
	h.add_child(go)


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
		"・開局徒手！槍枝要在地圖上撿取（E 拾取，可帶 2 把，1 / 2 / Q 切換）",
		"・你的裝備（頭盔、護甲…）是場外裝，會帶進比賽",
		"・安全區會逐步縮小，圈外持續受傷；小地圖可查看安全區",
		"・Shift 蹲下（更穩、更難被發現）　Ctrl 奔跑",
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
