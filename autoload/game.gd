extends Node
# 全域遊戲狀態：模式、關卡、分數、波次、技能、暫停/勝負

const Leaderboard = preload("res://scripts/data/leaderboard.gd")
const SkillDB = preload("res://scripts/data/skill_db.gd")
const LevelDB = preload("res://scripts/data/level_db.gd")
const ProgressDB = preload("res://scripts/data/progress_db.gd")

signal state_changed(new_state: int)
signal wave_started(wave: int)
signal wave_cleared(wave: int)
signal hit_marker(killed: bool)
signal skill_cast(id: String, evolved: bool)
signal kill_feed(text: String)
signal banner(text: String)
signal level_loaded                                                  # 關卡 / 地圖建構完成
signal toast(title: String, text: String, color: Color)         # 成就 / 任務 / 升級通知
signal hit_detail(zone: String, killed: bool, damage: float, pos: Vector3)   # 命中部位：head / body / leg
signal boss_changed(boss: Node)                                  # Boss 出場 / 死亡（HUD 血條）

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
var gameplay_boot: bool = false     # 目前這次場景載入是「開始遊戲」（需要建構關卡）；回到主選單時為 false
var level_ready: bool = false       # 關卡是否已建構完成
var load_progress: float = 0.0      # 載入進度 0~1（載入畫面用）
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

# 本局統計（結算畫面使用）
var run_stats: Dictionary = {}
var run_xp: int = 0
var run_level_start: int = 1
var run_level_coins: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_register_inputs()
	_apply_level(1)


func _register_inputs() -> void:
	# 蹲下：Shift　奔跑：Ctrl
	_add_key_action("sprint", KEY_CTRL)
	_add_key_action("crouch", KEY_SHIFT)
	_add_key_action("grenade", KEY_G)
	_add_key_action("medkit", KEY_H)
	_add_key_action("plate", KEY_T)


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
	gameplay_boot = true
	level_ready = false
	load_progress = 0.0
	show_lobby = false
	get_tree().paused = false
	get_tree().reload_current_scene()


func restart_run() -> void:
	begin_run(mode, level)


func return_to_lobby() -> void:
	skip_menu = false
	gameplay_boot = false
	level_ready = false
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
	run_stats = {}
	run_xp = 0
	run_level_coins = 0
	run_level_start = Save.player_level()
	Save.ensure_missions()
	set_state(State.MENU)


func set_state(new_state: State) -> void:
	state = new_state
	get_tree().paused = new_state != State.PLAYING
	# 主選單被 2D 封面完全遮住，關閉 3D 繪製可省下大量 GPU / 電力
	get_viewport().disable_3d = new_state == State.MENU
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
	record("kills_total")
	record("kills_zombie")
	add_xp(5)


# 大逃殺擊殺
func add_br_kill() -> void:
	kills += 1
	run_coins += 1
	Save.add_coins(1)
	record("kills_total")
	record("br_kills")
	add_xp(25)


# ---------- 統計 / 成就 / 任務 / 經驗值 ----------

# 累計統計 +n；同時推進每日任務並檢查成就
func record(stat: String, n: int = 1) -> void:
	Save.stats[stat] = int(Save.stats.get(stat, 0)) + n
	run_stats[stat] = int(run_stats.get(stat, 0)) + n
	_mission_progress(stat, n)
	_check_achievements()


# 取最大值型統計（例如玩家等級、皮膚數量）
func record_max(stat: String, value: int) -> void:
	if value > int(Save.stats.get(stat, 0)):
		Save.stats[stat] = value
		_check_achievements()


func _check_achievements() -> void:
	for id in ProgressDB.check_achievements(Save.stats, Save.achievements):
		var a: Dictionary = ProgressDB.achievement(id)
		Save.achievements[id] = Time.get_unix_time_from_system()
		Save.add_coins(int(a["coins"]))
		run_coins += int(a["coins"])
		toast.emit("成就解鎖", "%s　+%d 喪屍幣" % [a["name"], int(a["coins"])], Color(1.0, 0.82, 0.3))
		Sfx.play("pickup", 0.0, 1.3)
		if int(a["xp"]) > 0:
			add_xp(int(a["xp"]), false)


func _mission_progress(stat: String, n: int) -> void:
	Save.ensure_missions()
	for m in Save.missions["list"]:
		if str(m["stat"]) != stat or int(m["progress"]) >= int(m["target"]):
			continue
		m["progress"] = mini(int(m["progress"]) + n, int(m["target"]))
		if int(m["progress"]) >= int(m["target"]):
			toast.emit("每日任務完成", "%s（到大廳「任務」領取獎勵）" % m["text"], Color(0.4, 0.85, 0.55))
			Sfx.play("pickup", 0.0, 1.5)
			Save.stats["missions_done"] = int(Save.stats.get("missions_done", 0)) + 1
			_check_achievements()


func add_xp(n: int, announce: bool = true) -> void:
	var before := Save.player_level()
	Save.xp += n
	run_xp += n
	var after := Save.player_level()
	if after > before:
		var reward := 0
		for lv in range(before + 1, after + 1):
			reward += ProgressDB.level_reward(lv)
		Save.add_coins(reward)
		run_coins += reward
		run_level_coins += reward
		if announce:
			toast.emit("等級提升", "Lv.%d　獎勵 +%d 喪屍幣" % [after, reward], Color(0.5, 0.8, 1.0))
		record_max("player_level", after)


# 領取每日任務獎勵
func claim_mission(i: int) -> bool:
	Save.ensure_missions()
	var list: Array = Save.missions["list"]
	if i < 0 or i >= list.size():
		return false
	var m: Dictionary = list[i]
	if bool(m["claimed"]) or int(m["progress"]) < int(m["target"]):
		return false
	m["claimed"] = true
	Save.add_coins(int(m["coins"]))
	add_xp(int(m["xp"]), false)
	Save.save()
	return true


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
		record("br_games")
		if placement <= 3:
			record("br_top3")
		if won:
			record("br_wins")
		# 名次經驗：越前面越多，奪冠額外加成
		add_xp(maxi(BR_PLAYERS + 1 - placement, 0) * 12 + (150 if won else 0), false)
		var res := Save.record_br(placement, kills, BR_PLAYERS)
		result = {"mode": "br", "place": placement, "points": res["points"], "place_coins": res["coins"], "won": won}
		last_rank = Leaderboard.rank_of(Save.br_best_points, Save.br_wins, "br")
	else:
		if won:
			record("zombie_wins")
			add_xp(100 + 10 * level, false)
		var bonus := Save.record_level(level, score, won)
		result = {"mode": "zombie", "level": level, "clear_bonus": bonus, "won": won}
		last_rank = Leaderboard.rank_of(Save.level_total(), Save.cleared_level, "zombie")
	result["xp"] = run_xp
	result["level_before"] = run_level_start
	result["level_after"] = Save.player_level()
	result["level_coins"] = run_level_coins
	Save.save()
