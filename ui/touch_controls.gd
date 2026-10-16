extends Control
# 手機觸控操作：左側浮動搖桿移動、右側拖曳轉視角、右下按鈕（射擊、跳、蹲、換彈、開鏡、拾取、換槍）、
# 點技能列施放技能。多指同時操作；只在遊戲進行中顯示。

const SkillDB = preload("res://scripts/data/skill_db.gd")

const STICK_RADIUS: float = 90.0
const LOOK_SCALE: float = 1.6

# 按鈕：id、距右邊、距下邊、半徑、類型(hold/tap/toggle)、文字
const BUTTONS: Array = [
	{"id": "fire", "dx": 110.0, "dy": 110.0, "r": 64.0, "kind": "hold", "text": "射擊"},
	{"id": "crouch", "dx": 110.0, "dy": 250.0, "r": 36.0, "kind": "toggle", "text": "蹲下"},
	{"id": "interact", "dx": 110.0, "dy": 345.0, "r": 36.0, "kind": "tap", "text": "拾取"},
	{"id": "jump", "dx": 240.0, "dy": 80.0, "r": 40.0, "kind": "hold", "text": "跳"},
	{"id": "reload", "dx": 240.0, "dy": 170.0, "r": 36.0, "kind": "tap", "text": "換彈"},
	{"id": "aim", "dx": 240.0, "dy": 260.0, "r": 34.0, "kind": "toggle", "text": "開鏡"},
	{"id": "swap", "dx": 240.0, "dy": 350.0, "r": 32.0, "kind": "tap", "text": "換槍"},
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
var active_was: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS


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
	return Vector2(size.x - float(b["dx"]), size.y - float(b["dy"]))


func _button_visible(id: String) -> bool:
	if id == "swap":
		return Game.is_br()
	return true


func _pause_pos() -> Vector2:
	return Vector2(size.x * 0.5 + 310.0, 40.0)


func _process(_delta: float) -> void:
	# 輕點類動作：按下幾幀後放開，讓 is_action_just_pressed 能偵測到
	for action in tap_release.keys():
		tap_release[action] -= 1
		if tap_release[action] <= 0:
			Input.action_release(action)
			tap_release.erase(action)

	var active := _is_active()
	if active != active_was:
		active_was = active
		if not active:
			_reset_all()
	visible = active
	if active:
		_find_nodes()
		queue_redraw()


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
	if pos.distance_to(_pause_pos()) <= 34.0:
		Game.set_state(Game.State.PAUSED)
		return
	# 右下按鈕
	for b in BUTTONS:
		if not _button_visible(b["id"]):
			continue
		if pos.distance_to(_button_pos(b)) <= float(b["r"]) * 1.15:
			_button_down(idx, b)
			return
	# 技能列（殭屍關卡）
	if not Game.is_br() and hud != null:
		for i in hud.skill_slots.size():
			var root: Control = hud.skill_slots[i]["root"]
			if root.get_global_rect().grow(6.0).has_point(pos):
				if skills != null:
					skills.cast(SkillDB.ORDER[i])
				return
	# 左側：搖桿；其餘：轉視角
	if pos.x < size.x * 0.45 and move_finger == -1:
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
			if id == "swap":
				if weapon != null:
					weapon.switch_to(1 - weapon.active)
			else:
				_tap("reload" if id == "reload" else "interact")
		"toggle":
			toggles[id] = not bool(toggles.get(id, false))
			if id == "crouch":
				if toggles[id]:
					Input.action_press("crouch")
				else:
					Input.action_release("crouch")
			elif id == "aim" and weapon != null:
				weapon.touch_zoom = toggles[id]


func _set_hold(id: String, on: bool) -> void:
	if id == "fire":
		if weapon != null:
			weapon.touch_fire = on
	elif id == "jump":
		if on:
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
		var v := (pos - move_origin) / STICK_RADIUS
		_apply_move(v.limit_length(1.0))
	elif idx == look_finger and player != null:
		player.apply_look(rel * LOOK_SCALE)


# ---------- 繪製 ----------

func _draw() -> void:
	if not _is_active():
		return
	var font := ThemeDB.fallback_font
	# 搖桿
	if move_finger != -1:
		draw_circle(move_origin, STICK_RADIUS, Color(1, 1, 1, 0.12))
		draw_arc(move_origin, STICK_RADIUS, 0.0, TAU, 40, Color(1, 1, 1, 0.45), 3.0)
		var knob := move_origin + (move_pos - move_origin).limit_length(STICK_RADIUS)
		draw_circle(knob, 38.0, Color(1, 1, 1, 0.45))
	else:
		var hint := Vector2(200.0, size.y - 290.0)
		draw_arc(hint, STICK_RADIUS * 0.7, 0.0, TAU, 32, Color(1, 1, 1, 0.18), 2.0)
		draw_string(font, hint + Vector2(-24, 8), "移動", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.3))

	for b in BUTTONS:
		var id: String = b["id"]
		if not _button_visible(id):
			continue
		var on: bool = bool(held.get(id, false)) or bool(toggles.get(id, false))
		var c := _button_pos(b)
		var r: float = b["r"]
		var col := Color(1.0, 0.35, 0.25) if id == "fire" else Color(1, 1, 1)
		draw_circle(c, r, Color(col.r, col.g, col.b, 0.5 if on else 0.2))
		draw_arc(c, r, 0.0, TAU, 32, Color(col.r, col.g, col.b, 0.8 if on else 0.5), 3.0)
		var fs := 24 if id == "fire" else 18
		var w := font.get_string_size(str(b["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, c + Vector2(-w * 0.5, fs * 0.35), str(b["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.95))

	# 暫停
	var pp := _pause_pos()
	draw_circle(pp, 28.0, Color(1, 1, 1, 0.2))
	draw_rect(Rect2(pp + Vector2(-9, -11), Vector2(6, 22)), Color(1, 1, 1, 0.8))
	draw_rect(Rect2(pp + Vector2(3, -11), Vector2(6, 22)), Color(1, 1, 1, 0.8))
