extends Control
# 手機觸控操作（參考主流手遊射擊版面）：
#   左下：移動搖桿（可浮動）；左側上方：左手射擊鍵
#   右下：右手射擊鍵（大）、跳躍、蹲下、開鏡、換彈、拾取；大逃殺另有手榴彈 / 醫療包 / 護甲板
#   下方中央：武器欄（大逃殺，點選切槍）　左上：暫停（殭屍關卡的技能列在其右側）
#   空白處拖曳 = 轉視角（可選陀螺儀）。多指同時操作；只在遊戲進行中顯示。
# 設定可調整：按鍵大小、透明度、位置（拖曳編輯）、左手模式、陀螺儀。

const SkillDB = preload("res://scripts/data/skill_db.gd")
const WeaponDB = preload("res://scripts/data/weapon_db.gd")
const UIUtil = preload("res://ui/ui_util.gd")

const STICK_RADIUS: float = 80.0
const LOOK_SCALE: float = 1.6

# 錨點 R = 距右下角、L = 距左下角；dx / dy 為圓心距邊緣的距離（皆以高度 648 為基準）
# br = true 代表只在大逃殺顯示
const BUTTONS: Array = [
	{"id": "fire", "a": "R", "dx": 150.0, "dy": 215.0, "r": 64.0, "kind": "hold", "name": "射擊"},
	{"id": "jump", "a": "R", "dx": 66.0, "dy": 395.0, "r": 42.0, "kind": "hold", "name": "跳躍"},
	{"id": "crouch", "a": "R", "dx": 66.0, "dy": 92.0, "r": 38.0, "kind": "toggle", "name": "蹲下"},
	{"id": "aim", "a": "R", "dx": 296.0, "dy": 320.0, "r": 38.0, "kind": "toggle", "name": "開鏡"},
	{"id": "reload", "a": "R", "dx": 292.0, "dy": 150.0, "r": 36.0, "kind": "tap", "name": "換彈"},
	{"id": "interact", "a": "R", "dx": 370.0, "dy": 236.0, "r": 34.0, "kind": "tap", "name": "拾取"},
	{"id": "fire2", "a": "L", "dx": 96.0, "dy": 330.0, "r": 46.0, "kind": "hold", "name": "左手射擊"},
	{"id": "grenade", "a": "R", "dx": 168.0, "dy": 66.0, "r": 30.0, "kind": "tap", "name": "手榴彈", "br": true},
	{"id": "medkit", "a": "R", "dx": 236.0, "dy": 66.0, "r": 30.0, "kind": "tap", "name": "醫療包", "br": true},
	{"id": "plate", "a": "R", "dx": 304.0, "dy": 66.0, "r": 30.0, "kind": "tap", "name": "護甲板", "br": true},
]

var hud: Node
var player: Node
var weapon: Node
var skills: Node

var move_finger: int = -1
var move_origin: Vector2 = Vector2.ZERO
var move_pos: Vector2 = Vector2.ZERO
var look_finger: int = -1
var finger_button: Dictionary = {}     # 手指 index -> 按鈕 id
var toggles: Dictionary = {}           # 按鈕 id -> bool
var held: Dictionary = {}              # 按鈕 id -> bool（按住中）
var tap_release: Dictionary = {}       # action -> 剩餘幀數
var tap_flash: Dictionary = {}         # 按鈕 id -> 閃爍剩餘時間
var active_was: bool = false
var insets: Vector4 = Vector4.ZERO
var u: float = 1.0                     # 依螢幕高度縮放


# ---------- 版面（靜態：編輯器也會使用） ----------

# 左手模式：左右錨點對調
static func eff_anchor(b: Dictionary) -> String:
	var a: String = b["a"]
	if Save.left_handed:
		return "L" if a == "R" else "R"
	return a


static func button_pos(b: Dictionary, vp: Vector2, ins: Vector4, scale_u: float) -> Vector2:
	var dx := float(b["dx"])
	var dy := float(b["dy"])
	var ov: Variant = Save.touch_layout.get(b["id"])
	if ov is Array and (ov as Array).size() == 2:
		dx = float(ov[0])
		dy = float(ov[1])
	if eff_anchor(b) == "L":
		return Vector2(ins.x + dx * scale_u, vp.y - ins.w - dy * scale_u)
	return Vector2(vp.x - ins.z - dx * scale_u, vp.y - ins.w - dy * scale_u)


static func button_radius(b: Dictionary, scale_u: float) -> float:
	return float(b["r"]) * scale_u * Save.touch_scale


# 由螢幕座標換算回 dx / dy（編輯器拖曳用）
static func offsets_from_pos(b: Dictionary, pos: Vector2, vp: Vector2, ins: Vector4, scale_u: float) -> Array:
	var dy := (vp.y - ins.w - pos.y) / scale_u
	if eff_anchor(b) == "L":
		return [(pos.x - ins.x) / scale_u, dy]
	return [(vp.x - ins.z - pos.x) / scale_u, dy]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	resized.connect(_update_layout)
	_update_layout.call_deferred()


func _update_layout() -> void:
	insets = UIUtil.safe_insets(self)
	u = clampf(size.y / 648.0, 0.8, 1.25)


func _is_active() -> bool:
	return Save.touch_mode and Game.is_playing()


func _find_nodes() -> void:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
	if player != null and (weapon == null or not is_instance_valid(weapon)):
		weapon = player.get_node_or_null("Head/Camera3D/Weapon")
	if skills == null or not is_instance_valid(skills):
		skills = get_node_or_null("/root/Main/Skills")


func _button_pos(b: Dictionary) -> Vector2:
	return button_pos(b, size, insets, u)


func _button_r(b: Dictionary) -> float:
	return button_radius(b, u)


func _button_visible(b: Dictionary) -> bool:
	if bool(b.get("br", false)):
		return Game.is_br()
	return true


func _alpha(a: float) -> float:
	return a * Save.touch_opacity / 0.85


func _pause_pos() -> Vector2:
	return Vector2(insets.x + 34.0 * u, insets.y + 34.0 * u)


func _stick_home() -> Vector2:
	if Save.left_handed:
		return Vector2(size.x - insets.z - 190.0 * u, size.y - insets.w - 150.0 * u)
	return Vector2(insets.x + 190.0 * u, size.y - insets.w - 150.0 * u)


# 搖桿觸發區：預設左側 42%；左手模式為右側 42%
func _in_stick_zone(pos: Vector2) -> bool:
	if Save.left_handed:
		return pos.x > size.x * 0.58
	return pos.x < size.x * 0.42


func _slot_rect(i: int) -> Rect2:
	var w := 150.0 * u
	var h := 42.0 * u
	var gap := 10.0 * u
	var x := size.x * 0.5 - w - gap * 0.5 + float(i) * (w + gap)
	return Rect2(x, size.y - insets.w - h - 10.0 * u, w, h)


func _process(delta: float) -> void:
	# 輕點類動作：按下幾幀後放開，讓 is_action_just_pressed 能偵測到
	for action in tap_release.keys():
		tap_release[action] -= 1
		if tap_release[action] <= 0:
			Input.action_release(action)
			tap_release.erase(action)
	for id in tap_flash.keys():
		tap_flash[id] -= delta
		if tap_flash[id] <= 0.0:
			tap_flash.erase(id)

	var active := _is_active()
	if active != active_was:
		active_was = active
		if not active:
			_reset_all()
	visible = active
	if active:
		_find_nodes()
		_gyro(delta)
		queue_redraw()


# 陀螺儀瞄準：以手機轉動量微調視角（實測方向若相反，可在設定中反轉）
func _gyro(delta: float) -> void:
	if not Save.gyro_aim or player == null or not OS.has_feature("mobile"):
		return
	if bool(player.get("is_dead")) or bool(player.get("skydiving")):
		return
	var g := Input.get_gyroscope()
	var yaw := -g.y * (-1.0 if Save.gyro_invert_x else 1.0)
	var pitch := -g.x * (-1.0 if Save.gyro_invert_y else 1.0)
	var k := Save.gyro_sens * delta * 1.2 * lerpf(1.0, 0.6, float(player.get("ads_factor")))
	if absf(yaw) > 0.01 or absf(pitch) > 0.01:
		player.call("apply_look_rad", yaw * k, pitch * k)


func _reset_all() -> void:
	move_finger = -1
	look_finger = -1
	finger_button.clear()
	held.clear()
	_apply_move(Vector2.ZERO)
	Input.action_release("jump")
	Input.action_release("crouch")
	Input.action_release("sprint")
	toggles.clear()
	if weapon != null and is_instance_valid(weapon):
		weapon.touch_fire = false
		weapon.touch_zoom = false


func _tap(action: String) -> void:
	Input.action_press(action)
	tap_release[action] = 3


func _apply_move(v: Vector2) -> void:
	_set_axis("move_forward", maxf(-v.y, 0.0))
	_set_axis("move_back", maxf(v.y, 0.0))
	_set_axis("move_left", maxf(-v.x, 0.0))
	_set_axis("move_right", maxf(v.x, 0.0))
	# 把搖桿推到底往前：自動奔跑
	if v.length() > 0.92 and v.y < -0.6:
		Input.action_press("sprint")
	else:
		Input.action_release("sprint")


func _set_axis(action: String, strength: float) -> void:
	if strength < 0.12:
		Input.action_release(action)
	else:
		Input.action_press(action, strength)


func _input(event: InputEvent) -> void:
	if not _is_active():
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_press(t.index, t.position)
		else:
			_release(t.index)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_drag(d.index, d.position, d.relative)


func _press(idx: int, pos: Vector2) -> void:
	# 暫停鈕
	if pos.distance_to(_pause_pos()) <= 36.0 * u:
		# 延到本幀輸入處理完再暫停，避免同一次點擊的滑鼠模擬事件落到剛出現的選單上
		Game.set_state.call_deferred(Game.State.PAUSED)
		return
	# 操作按鈕
	for b in BUTTONS:
		if not _button_visible(b):
			continue
		if pos.distance_to(_button_pos(b)) <= _button_r(b) * 1.18:
			_button_down(idx, b)
			return
	# 武器欄（大逃殺）
	if Game.is_br() and weapon != null:
		for i in 2:
			if _slot_rect(i).grow(6.0).has_point(pos):
				weapon.switch_to(i)
				tap_flash["slot%d" % i] = 0.18
				return
	# 技能列（殭屍關卡）
	if not Game.is_br() and hud != null:
		for i in hud.skill_slots.size():
			var root: Control = hud.skill_slots[i]["root"]
			if root.get_global_rect().grow(6.0).has_point(pos):
				if skills != null:
					skills.cast(SkillDB.ORDER[i])
				tap_flash["skill%d" % i] = 0.18
				return
	# 搖桿區：浮動搖桿；其餘：轉視角
	if _in_stick_zone(pos) and move_finger == -1:
		move_finger = idx
		move_origin = pos
		move_pos = pos
	elif look_finger == -1:
		look_finger = idx


func _button_down(idx: int, b: Dictionary) -> void:
	var id: String = b["id"]
	match str(b["kind"]):
		"hold":
			finger_button[idx] = id
			held[id] = true
			_set_hold(id, true)
		"tap":
			tap_flash[id] = 0.15
			match id:
				"reload":
					_tap("reload")
				"interact":
					_tap("interact")
				"grenade":
					if player != null:
						player.call("throw_grenade")
				"medkit":
					if player != null:
						player.call("start_use", "medkit")
				"plate":
					if player != null:
						player.call("start_use", "plate")
		"toggle":
			toggles[id] = not bool(toggles.get(id, false))
			if id == "crouch":
				if toggles[id]:
					Input.action_press("crouch")
				else:
					Input.action_release("crouch")
			elif id == "aim" and weapon != null:
				weapon.touch_zoom = toggles[id]


func _set_hold(id: String, _on: bool) -> void:
	if id == "fire" or id == "fire2":
		if weapon != null:
			weapon.touch_fire = bool(held.get("fire", false)) or bool(held.get("fire2", false))
	elif id == "jump":
		if bool(held.get("jump", false)):
			Input.action_press("jump")
		else:
			Input.action_release("jump")


func _release(idx: int) -> void:
	if idx == move_finger:
		move_finger = -1
		_apply_move(Vector2.ZERO)
	elif idx == look_finger:
		look_finger = -1
	if finger_button.has(idx):
		var id: String = finger_button[idx]
		finger_button.erase(idx)
		held[id] = false
		_set_hold(id, false)


func _drag(idx: int, pos: Vector2, rel: Vector2) -> void:
	if idx == move_finger:
		move_pos = pos
		var v := (pos - move_origin) / (STICK_RADIUS * u)
		_apply_move(v.limit_length(1.0))
	elif idx == look_finger and player != null:
		player.apply_look(rel * LOOK_SCALE)
	elif player != null and str(finger_button.get(idx, "")) in ["fire", "fire2"]:
		# 射擊鍵可拖曳：按住射擊的同時滑動手指就能轉動視角（同 Free Fire）
		player.apply_look(rel * LOOK_SCALE)


# ---------- 繪製 ----------

func _draw() -> void:
	if not _is_active():
		return
	_draw_stick()
	for b in BUTTONS:
		if _button_visible(b):
			_draw_button(b)
	if Game.is_br():
		_draw_slots()
	_draw_pause()


func _draw_stick() -> void:
	var rad := STICK_RADIUS * u
	var base := move_origin
	var knob := base
	var on := move_finger != -1
	if on:
		knob = base + (move_pos - base).limit_length(rad)
	else:
		base = _stick_home()
		knob = base
	draw_circle(base, rad, Color(0, 0, 0, _alpha(0.22 if on else 0.16)))
	draw_arc(base, rad, 0.0, TAU, 48, Color(1, 1, 1, _alpha(0.6 if on else 0.35)), 3.0)
	draw_arc(base, rad * 0.45, 0.0, TAU, 32, Color(1, 1, 1, _alpha(0.12)), 2.0)
	# 方向箭頭
	for k in 4:
		var d := Vector2.from_angle(float(k) * PI * 0.5)
		var c := base + d * rad * 0.82
		var p := d.orthogonal()
		draw_colored_polygon(PackedVector2Array([c + d * 7.0, c - d * 4.0 + p * 7.0, c - d * 4.0 - p * 7.0]), Color(1, 1, 1, _alpha(0.35)))
	draw_circle(knob, 34.0 * u, Color(0.1, 0.1, 0.12, _alpha(0.7)))
	draw_circle(knob, 34.0 * u, Color(1, 1, 1, _alpha(0.22)))
	draw_arc(knob, 34.0 * u, 0.0, TAU, 32, Color(1, 1, 1, _alpha(0.75 if on else 0.45)), 3.0)


# 道具按鈕上顯示持有數量
func _item_count(id: String) -> int:
	if player == null:
		return 0
	match id:
		"grenade":
			return int(player.get("grenades"))
		"medkit":
			return int(player.get("medkits"))
		"plate":
			return int(player.get("plates"))
	return -1


func _draw_button(b: Dictionary) -> void:
	var id: String = b["id"]
	var on: bool = bool(held.get(id, false)) or bool(toggles.get(id, false)) or tap_flash.has(id)
	var c := _button_pos(b)
	var r := _button_r(b)
	var cnt := _item_count(id)
	var empty := cnt == 0
	var accent := Color(1.0, 0.4, 0.28) if id.begins_with("fire") else Color(1, 1, 1)
	match id:
		"grenade":
			accent = Color(0.6, 0.95, 0.5)
		"medkit":
			accent = Color(1.0, 0.5, 0.45)
		"plate":
			accent = Color(0.55, 0.75, 1.0)
	var dim := 0.4 if empty else 1.0
	draw_circle(c, r, Color(0, 0, 0, _alpha(0.3)))
	if on:
		draw_circle(c, r, Color(accent.r, accent.g, accent.b, _alpha(0.4)))
	draw_arc(c, r, 0.0, TAU, 40, Color(accent.r, accent.g, accent.b, _alpha((0.95 if on else 0.6) * dim)), 3.5 if id == "fire" else 3.0)
	var ic := Color(1, 1, 1, _alpha((0.95 if on else 0.8) * dim))
	var s := r * 0.5
	match id:
		"fire", "fire2":
			# 準星 + 子彈
			draw_arc(c, s * 0.9, 0.0, TAU, 28, ic, 3.0)
			draw_circle(c, s * 0.22, ic)
			for k in 4:
				var d := Vector2.from_angle(float(k) * PI * 0.5)
				draw_line(c + d * s * 0.9, c + d * s * 1.35, ic, 3.0)
		"jump":
			draw_polyline(PackedVector2Array([c + Vector2(-s, s * 0.35), c + Vector2(0, -s * 0.45), c + Vector2(s, s * 0.35)]), ic, 4.5)
			draw_polyline(PackedVector2Array([c + Vector2(-s, s * 0.95), c + Vector2(0, s * 0.15), c + Vector2(s, s * 0.95)]), Color(ic.r, ic.g, ic.b, ic.a * 0.5), 4.5)
		"crouch":
			draw_polyline(PackedVector2Array([c + Vector2(-s, -s * 0.35), c + Vector2(0, s * 0.45), c + Vector2(s, -s * 0.35)]), ic, 4.5)
			draw_line(c + Vector2(-s, s * 0.95), c + Vector2(s, s * 0.95), ic, 4.0)
		"aim":
			draw_arc(c, s * 1.05, 0.0, TAU, 28, ic, 3.0)
			draw_line(c + Vector2(-s * 1.5, 0), c + Vector2(-s * 0.45, 0), ic, 3.0)
			draw_line(c + Vector2(s * 0.45, 0), c + Vector2(s * 1.5, 0), ic, 3.0)
			draw_line(c + Vector2(0, -s * 1.5), c + Vector2(0, -s * 0.45), ic, 3.0)
			draw_line(c + Vector2(0, s * 0.45), c + Vector2(0, s * 1.5), ic, 3.0)
			draw_circle(c, 2.5, ic)
		"reload":
			draw_arc(c, s * 1.0, -0.4, TAU - 1.1, 28, ic, 4.0)
			var tip := c + Vector2.from_angle(-0.4) * s
			draw_colored_polygon(PackedVector2Array([tip + Vector2(8, -6), tip + Vector2(-9, -7), tip + Vector2(0, 11)]), ic)
		"interact":
			# 拾取：往下的箭頭 + 底座
			draw_line(c + Vector2(0, -s * 1.0), c + Vector2(0, s * 0.5), ic, 4.5)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.7, s * 0.15), c + Vector2(s * 0.7, s * 0.15), c + Vector2(0, s * 0.95)]), ic)
			draw_line(c + Vector2(-s * 0.9, s * 1.25), c + Vector2(s * 0.9, s * 1.25), ic, 4.0)
		"grenade":
			draw_circle(c + Vector2(0, s * 0.15), s * 0.95, ic)
			draw_rect(Rect2(c + Vector2(-s * 0.25, -s * 1.15), Vector2(s * 0.5, s * 0.35)), ic)
			draw_arc(c + Vector2(s * 0.45, -s * 1.0), s * 0.35, PI, TAU * 0.9, 8, ic, 2.5)
		"medkit":
			draw_rect(Rect2(c + Vector2(-s * 0.3, -s * 1.0), Vector2(s * 0.6, s * 2.0)), ic)
			draw_rect(Rect2(c + Vector2(-s * 1.0, -s * 0.3), Vector2(s * 2.0, s * 0.6)), ic)
		"plate":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 1.1), c + Vector2(s * 0.95, -s * 0.7), c + Vector2(s * 0.85, s * 0.3), c + Vector2(0, s * 1.15), c + Vector2(-s * 0.85, s * 0.3), c + Vector2(-s * 0.95, -s * 0.7)]), ic)
	# 道具數量角標
	if cnt >= 0:
		var font := ThemeDB.fallback_font
		var bp := c + Vector2(r * 0.62, -r * 0.62)
		draw_circle(bp, 11.0 * u, Color(0.05, 0.05, 0.08, _alpha(0.9)))
		draw_string(font, bp + Vector2(-5.0, 6.0) * u, str(cnt), HORIZONTAL_ALIGNMENT_LEFT, -1, int(17.0 * u), Color(1, 1, 1, _alpha(0.95)))


func _draw_slots() -> void:
	if weapon == null:
		return
	var font := ThemeDB.fallback_font
	for i in 2:
		var rect := _slot_rect(i)
		var slot: Dictionary = weapon.slots[i]
		var is_active: bool = int(weapon.active) == i
		var flash: bool = tap_flash.has("slot%d" % i)
		var bg := Color(0.0, 0.0, 0.0, _alpha(0.42))
		if is_active:
			bg = Color(0.45, 0.2, 0.12, _alpha(0.6))
		draw_rect(rect, bg)
		draw_rect(rect, Color(1.0, 0.7, 0.3, _alpha(0.95)) if (is_active or flash) else Color(1, 1, 1, _alpha(0.35)), false, 3.0 if is_active else 2.0)
		var name_text := "空"
		if not slot.is_empty():
			name_text = str((WeaponDB.WEAPONS[slot["id"]] as Dictionary)["name"]).get_slice(" ", 0)
		var fs := int(19.0 * u)
		draw_string(font, rect.position + Vector2(10.0 * u, rect.size.y * 0.5 + fs * 0.36), "%d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.85, 0.5))
		draw_string(font, rect.position + Vector2(32.0 * u, rect.size.y * 0.5 + fs * 0.36), name_text, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 40.0 * u, fs, Color(1, 1, 1, 0.95 if not slot.is_empty() else 0.4))


func _draw_pause() -> void:
	var pp := _pause_pos()
	var r := 26.0 * u
	draw_circle(pp, r, Color(0, 0, 0, _alpha(0.35)))
	draw_arc(pp, r, 0.0, TAU, 32, Color(1, 1, 1, _alpha(0.6)), 2.5)
	draw_rect(Rect2(pp + Vector2(-8, -10) * u, Vector2(5, 20) * u), Color(1, 1, 1, _alpha(0.9)))
	draw_rect(Rect2(pp + Vector2(3, -10) * u, Vector2(5, 20) * u), Color(1, 1, 1, _alpha(0.9)))
