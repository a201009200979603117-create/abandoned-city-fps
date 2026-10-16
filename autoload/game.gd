extends Node
# 全域遊戲狀態：模式、關卡、分數、波次、技能、暫停/勝負

const Leaderboard = preload("res://scripts/data/leaderboard.gd")
const SkillDB = preload("res://scripts/data/skill_db.gd")
const LevelDB = preload("res://scripts/data/level_db.gd")

signal state_changed(new_state: int)
signal wave_started(wave: int)
signal wave_cleared(wave: int)
signal hit_marker(killed: bool)
signal skill_cast(id: String, evolved: bool)
signal kill_feed(text: String)
signal banner(text: String)

enum State { MENU, PLAYING, PAUSED, WON, LOST, SKILL }

const WIN_BONUS: int = 1000
const BR_PLAYERS: int = 12

var state: State = State.MENU
var score: int = 0
var kills: int = 0
var wave: int = 0
var total_waves: int = 5
var enemies_remaining: int = 0
var skip_menu: bool = false
var show_lobby: bool = false

# 模式："zombie"（殭屍關卡）或 "br"（大逃殺）
var mode: String = "zombie"
var level: int = 1
var level_cfg: Dictionary = {}

var run_coins: int = 0
var last_rank: int = 0
var skill_levels: Dictionary = {}
var skill_evolved: Dictionary = {}

# 結算資訊
var result: Dictionary = {}

# 大逃殺
var br_alive: int = BR_PLAYERS
var placement: int = 0
var airdrop_item: String = ""
var victory_pending: bool = false
var killed_by: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_register_inputs()
	_apply_level(1)


func _register_inputs() -> void:
	# 蹲下：Shift　奔跑：Ctrl
	_add_key_action("sprint", KEY_CTRL)
	_add_key_action("crouch", KEY_SHIFT)


func _add_key_action(action: String, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)


func _apply_level(n: int) -> void:
	level = clampi(n, 1, LevelDB.count())
	level_cfg = LevelDB.get_level(level)
	total_waves = int(level_cfg["waves"])


# 設定並開始一場遊戲（重新載入場景，確保槍枝/關卡/裝備全部重新套用）
func begin_run(new_mode: String, new_level: int = 1) -> void:
	mode = new_mode
	_apply_level(new_level)
	skip_menu = true
	show_lobby = false
	get_tree().paused = false
	get_tree().reload_current_scene()


func restart_run() -> void:
	begin_run(mode, level)


func return_to_lobby() -> void:
	skip_menu = false
	show_lobby = true
	get_tree().paused = false
	get_tree().reload_current_scene()


func reset() -> void:
	score = 0
	kills = 0
	wave = 0
	enemies_remaining = 0
	run_coins = 0
	last_rank = 0
	skill_levels = {}
	skill_evolved = {}
	result = {}
	br_alive = BR_PLAYERS
	placement = 0
	airdrop_item = ""
	victory_pending = false
	killed_by = ""
	set_state(State.MENU)


func set_state(new_state: State) -> void:
	state = new_state
	get_tree().paused = new_state != State.PLAYING
	if new_state == State.PLAYING:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	state_changed.emit(new_state)


func is_playing() -> bool:
	return state == State.PLAYING


func is_br() -> bool:
	return mode == "br"


func add_kill(points: int) -> void:
	kills += 1
	score += points
	run_coins += 1
	Save.add_coins(1)


# 大逃殺擊殺
func add_br_kill() -> void:
	kills += 1
	run_coins += 1
	Save.add_coins(1)


func skill_level(id: String) -> int:
	return int(skill_levels.get(id, 0))


func is_evolved(id: String) -> bool:
	return bool(skill_evolved.get(id, false))


# 可供挑選的選項：[{id, kind: "learn"|"upgrade"|"evolve"}]
func skill_options(count: int = 3) -> Array:
	var pool: Array = []
	for id in SkillDB.ORDER:
		var lv := skill_level(id)
		if lv == 0:
			pool.append({"id": id, "kind": "learn"})
		elif lv < SkillDB.MAX_LEVEL:
			pool.append({"id": id, "kind": "upgrade"})
		elif not is_evolved(id):
			pool.append({"id": id, "kind": "evolve"})
	pool.shuffle()
	# 可突破的技能優先出現，讓玩家有機會解鎖
	pool.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["kind"] == "evolve" and b["kind"] != "evolve")
	return pool.slice(0, count)


func choose_skill(option: Dictionary) -> void:
	var id: String = option["id"]
	match option["kind"]:
		"learn":
			skill_levels[id] = 1
		"upgrade":
			skill_levels[id] = skill_level(id) + 1
		"evolve":
			skill_evolved[id] = true


func win() -> void:
	if state != State.PLAYING and state != State.SKILL:
		return
	Sfx.play("win")
	if is_br():
		placement = 1
	else:
		score += WIN_BONUS
	_finish_run(true)
	set_state(State.WON)


func lose() -> void:
	if state != State.PLAYING:
		return
	Sfx.play("lose")
	if is_br():
		placement = maxi(br_alive, 1)
	_finish_run(false)
	set_state(State.LOST)


func _finish_run(won: bool) -> void:
	if is_br():
		var res := Save.record_br(placement, kills, BR_PLAYERS)
		result = {"mode": "br", "place": placement, "points": res["points"], "place_coins": res["coins"], "won": won}
		last_rank = Leaderboard.rank_of(Save.br_best_points, Save.br_wins, "br")
	else:
		var bonus := Save.record_level(level, score, won)
		result = {"mode": "zombie", "level": level, "clear_bonus": bonus, "won": won}
		last_rank = Leaderboard.rank_of(Save.level_total(), Save.cleared_level, "zombie")
