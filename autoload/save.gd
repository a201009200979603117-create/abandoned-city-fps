extends Node
# 玩家存檔：喪屍幣、皮膚、選用槍枝、設定、最高分。存於 user://profile.cfg

const WeaponDB = preload("res://scripts/data/weapon_db.gd")
const EquipDB = preload("res://scripts/data/equip_db.gd")
const LevelDB = preload("res://scripts/data/level_db.gd")
const ProgressDB = preload("res://scripts/data/progress_db.gd")

var PATH: String = OS.get_environment("AC_SAVE") if OS.get_environment("AC_SAVE") != "" else "user://profile.cfg"   # 測試可用環境變數 AC_SAVE 改用獨立存檔
const DRAW_COST: int = 10
const DUPLICATE_REFUND: int = 4

var coins: int = 0
var total_kills: int = 0
var best_score: int = 0
var best_wave: int = 0
var runs: int = 0
var draws: int = 0
var selected_weapon: String = "rifle"
var selected_skin: String = "default"
var owned_skins: Array = ["default"]

# 裝備與進度
var owned_equip: Array = []
var equipped: Dictionary = {}
var cleared_level: int = 0
var level_best: Dictionary = {}
var br_games: int = 0
var br_wins: int = 0
var br_best_place: int = 0
var br_kills: int = 0
var br_best_points: int = 0

# 設定
var volume: float = 0.8
var music_volume: float = 0.7
var sensitivity: float = 1.0
var fov: float = 75.0
var fullscreen: bool = false
var motion_blur: float = 0.6   # 0 = 關閉
var touch_mode: bool = OS.has_feature("mobile")   # 手機預設啟用觸控操作
var quality: int = -1            # 畫質：0 低 / 1 中 / 2 高；-1 = 依裝置自動
var touch_scale: float = 1.0     # 觸控按鍵大小倍率
var touch_opacity: float = 0.85  # 觸控按鍵不透明度
var touch_layout: Dictionary = {}   # 按鍵 id -> [dx, dy]（自訂位置）
var left_handed: bool = false   # 左手模式：左右配置對調
var gyro_aim: bool = false
var gyro_sens: float = 1.0
var gyro_invert_x: bool = false
var gyro_invert_y: bool = false

# 成長
var xp: int = 0
var stats: Dictionary = {}
var achievements: Dictionary = {}
var attachments: Dictionary = {}     # 槍枝 id -> {配件: 等級}
var missions: Dictionary = {}        # {date, list}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_profile()
	apply_settings()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save()


func load_profile() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	coins = int(cfg.get_value("profile", "coins", 0))
	total_kills = int(cfg.get_value("profile", "total_kills", 0))
	best_score = int(cfg.get_value("profile", "best_score", 0))
	best_wave = int(cfg.get_value("profile", "best_wave", 0))
	runs = int(cfg.get_value("profile", "runs", 0))
	draws = int(cfg.get_value("profile", "draws", 0))
	selected_weapon = str(cfg.get_value("profile", "selected_weapon", "rifle"))
	selected_skin = str(cfg.get_value("profile", "selected_skin", "default"))
	cleared_level = int(cfg.get_value("profile", "cleared_level", 0))
	br_games = int(cfg.get_value("profile", "br_games", 0))
	br_wins = int(cfg.get_value("profile", "br_wins", 0))
	br_best_place = int(cfg.get_value("profile", "br_best_place", 0))
	br_kills = int(cfg.get_value("profile", "br_kills", 0))
	br_best_points = int(cfg.get_value("profile", "br_best_points", 0))
	var lb: Variant = cfg.get_value("profile", "level_best", {})
	if lb is Dictionary:
		level_best = lb
	var oe: Variant = cfg.get_value("profile", "owned_equip", [])
	if oe is Array:
		owned_equip = oe.filter(func(id: Variant) -> bool: return EquipDB.exists(str(id)))
	var eq: Variant = cfg.get_value("profile", "equipped", {})
	if eq is Dictionary:
		for slot in eq:
			if owned_equip.has(eq[slot]) and EquipDB.slot_of(str(eq[slot])) == slot:
				equipped[slot] = eq[slot]
	var skins: Variant = cfg.get_value("profile", "owned_skins", ["default"])
	if skins is Array:
		owned_skins = skins
	volume = float(cfg.get_value("settings", "volume", 0.8))
	music_volume = float(cfg.get_value("settings", "music_volume", 0.7))
	sensitivity = float(cfg.get_value("settings", "sensitivity", 1.0))
	fov = float(cfg.get_value("settings", "fov", 75.0))
	fullscreen = bool(cfg.get_value("settings", "fullscreen", false))
	motion_blur = float(cfg.get_value("settings", "motion_blur", 0.6))
	touch_mode = bool(cfg.get_value("settings", "touch_mode", OS.has_feature("mobile")))
	quality = int(cfg.get_value("settings", "quality", -1))
	touch_scale = float(cfg.get_value("settings", "touch_scale", 1.0))
	touch_opacity = float(cfg.get_value("settings", "touch_opacity", 0.85))
	left_handed = bool(cfg.get_value("settings", "left_handed", false))
	gyro_aim = bool(cfg.get_value("settings", "gyro_aim", false))
	gyro_sens = float(cfg.get_value("settings", "gyro_sens", 1.0))
	gyro_invert_x = bool(cfg.get_value("settings", "gyro_invert_x", false))
	gyro_invert_y = bool(cfg.get_value("settings", "gyro_invert_y", false))
	var tl: Variant = cfg.get_value("settings", "touch_layout", {})
	touch_layout = tl if tl is Dictionary else {}
	xp = int(cfg.get_value("progress", "xp", 0))
	var st: Variant = cfg.get_value("progress", "stats", {})
	stats = st if st is Dictionary else {}
	var ac: Variant = cfg.get_value("progress", "achievements", {})
	achievements = ac if ac is Dictionary else {}
	var at: Variant = cfg.get_value("progress", "attachments", {})
	attachments = at if at is Dictionary else {}
	var ms: Variant = cfg.get_value("progress", "missions", {})
	missions = ms if ms is Dictionary else {}
	# 防呆：資料表若改版，回到預設
	if not WeaponDB.WEAPONS.has(selected_weapon):
		selected_weapon = "rifle"
	if not WeaponDB.SKINS.has(selected_skin) or not owned_skins.has(selected_skin):
		selected_skin = "default"
	if not owned_skins.has("default"):
		owned_skins.append("default")


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "coins", coins)
	cfg.set_value("profile", "total_kills", total_kills)
	cfg.set_value("profile", "best_score", best_score)
	cfg.set_value("profile", "best_wave", best_wave)
	cfg.set_value("profile", "runs", runs)
	cfg.set_value("profile", "draws", draws)
	cfg.set_value("profile", "selected_weapon", selected_weapon)
	cfg.set_value("profile", "selected_skin", selected_skin)
	cfg.set_value("profile", "owned_skins", owned_skins)
	cfg.set_value("profile", "owned_equip", owned_equip)
	cfg.set_value("profile", "equipped", equipped)
	cfg.set_value("profile", "cleared_level", cleared_level)
	cfg.set_value("profile", "level_best", level_best)
	cfg.set_value("profile", "br_games", br_games)
	cfg.set_value("profile", "br_wins", br_wins)
	cfg.set_value("profile", "br_best_place", br_best_place)
	cfg.set_value("profile", "br_kills", br_kills)
	cfg.set_value("profile", "br_best_points", br_best_points)
	cfg.set_value("settings", "volume", volume)
	cfg.set_value("settings", "music_volume", music_volume)
	cfg.set_value("settings", "sensitivity", sensitivity)
	cfg.set_value("settings", "fov", fov)
	cfg.set_value("settings", "fullscreen", fullscreen)
	cfg.set_value("settings", "motion_blur", motion_blur)
	cfg.set_value("settings", "touch_mode", touch_mode)
	cfg.set_value("settings", "quality", quality)
	cfg.set_value("settings", "touch_scale", touch_scale)
	cfg.set_value("settings", "touch_opacity", touch_opacity)
	cfg.set_value("settings", "left_handed", left_handed)
	cfg.set_value("settings", "gyro_aim", gyro_aim)
	cfg.set_value("settings", "gyro_sens", gyro_sens)
	cfg.set_value("settings", "gyro_invert_x", gyro_invert_x)
	cfg.set_value("settings", "gyro_invert_y", gyro_invert_y)
	cfg.set_value("settings", "touch_layout", touch_layout)
	cfg.set_value("progress", "xp", xp)
	cfg.set_value("progress", "stats", stats)
	cfg.set_value("progress", "achievements", achievements)
	cfg.set_value("progress", "attachments", attachments)
	cfg.set_value("progress", "missions", missions)
	cfg.save(PATH)


func reset_profile() -> void:
	coins = 0
	total_kills = 0
	best_score = 0
	best_wave = 0
	runs = 0
	draws = 0
	selected_weapon = "rifle"
	selected_skin = "default"
	owned_skins = ["default"]
	owned_equip = []
	equipped = {}
	cleared_level = 0
	level_best = {}
	br_games = 0
	br_wins = 0
	br_best_place = 0
	br_kills = 0
	br_best_points = 0
	xp = 0
	stats = {}
	achievements = {}
	attachments = {}
	missions = {}
	save()


# 拾取提示文字（手機點按鈕、桌機按 E）
func interact_hint() -> String:
	return "點「拾取」鈕" if touch_mode else "按 E "


func apply_settings() -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(bus, volume <= 0.001)
	if DisplayServer.get_name() == "headless":
		return
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)


func add_coins(n: int) -> void:
	coins += n


# ---------- 畫質 ----------

# 實際使用的畫質：0 低 / 1 中 / 2 高
func effective_quality() -> int:
	if quality >= 0:
		return clampi(quality, 0, 2)
	if OS.has_feature("web"):
		return 0
	if touch_mode or OS.has_feature("mobile"):
		return 1
	return 2


# ---------- 等級 ----------

func player_level() -> int:
	return ProgressDB.level_for(xp)


# ---------- 槍枝配件 ----------

func attach_level(weapon_id: String, kind: String) -> int:
	var d: Variant = attachments.get(weapon_id, {})
	if d is Dictionary:
		return int((d as Dictionary).get(kind, 0))
	return 0


# 升級配件：成功回傳 true
func upgrade_attach(weapon_id: String, kind: String) -> bool:
	var lv := attach_level(weapon_id, kind)
	var cost := ProgressDB.attach_cost(kind, lv)
	if lv >= ProgressDB.ATTACH_MAX or coins < cost:
		return false
	coins -= cost
	var d: Dictionary = attachments.get(weapon_id, {})
	d[kind] = lv + 1
	attachments[weapon_id] = d
	save()
	return true


func attach_maxed_count() -> int:
	var n := 0
	for wid in attachments:
		for k in (attachments[wid] as Dictionary):
			if int(attachments[wid][k]) >= ProgressDB.ATTACH_MAX:
				n += 1
	return n


# ---------- 每日任務 ----------

func ensure_missions() -> void:
	var today := Time.get_date_string_from_system()
	if str(missions.get("date", "")) != today or not missions.has("list"):
		missions = {"date": today, "list": ProgressDB.generate(today)}
		save()


func mission_claimable_count() -> int:
	ensure_missions()
	var n := 0
	for m in missions["list"]:
		if int(m["progress"]) >= int(m["target"]) and not bool(m["claimed"]):
			n += 1
	return n


func record_run(score: int, wave: int, kills: int) -> void:
	runs += 1
	total_kills += kills
	best_score = maxi(best_score, score)
	best_wave = maxi(best_wave, wave)
	save()


func can_draw() -> bool:
	return coins >= DRAW_COST


# 抽獎：回傳 {skin: String, duplicate: bool}；金幣不足回傳空字典
func draw_skin() -> Dictionary:
	if not can_draw():
		return {}
	coins -= DRAW_COST
	draws += 1
	var total := 0.0
	for id in WeaponDB.SKINS:
		total += WeaponDB.RARITY[WeaponDB.SKINS[id]["rarity"]]["weight"]
	var roll := randf() * total
	var picked := "default"
	for id in WeaponDB.SKINS:
		roll -= WeaponDB.RARITY[WeaponDB.SKINS[id]["rarity"]]["weight"]
		if roll <= 0.0:
			picked = id
			break
	var dup := owned_skins.has(picked)
	if dup:
		coins += DUPLICATE_REFUND
	else:
		owned_skins.append(picked)
	save()
	return {"skin": picked, "duplicate": dup}


# ---------- 裝備 ----------

func equip_totals() -> Dictionary:
	return EquipDB.totals(equipped)


func buy_equip(id: String) -> bool:
	if owned_equip.has(id) or EquipDB.airdrop_only(id):
		return false
	var price := EquipDB.cost(id)
	if coins < price:
		return false
	coins -= price
	owned_equip.append(id)
	equipped[EquipDB.slot_of(id)] = id
	save()
	return true


func equip_item(id: String) -> void:
	if owned_equip.has(id):
		equipped[EquipDB.slot_of(id)] = id
		save()


func unequip_slot(slot: String) -> void:
	equipped.erase(slot)
	save()


# 空投：隨機取得一件尚未擁有的裝備（稀有以上）。回傳裝備 id；全部擁有則回傳空字串並補償喪屍幣
func grant_airdrop() -> String:
	var pool: Array = []
	var total := 0.0
	for id in EquipDB.all_ids():
		if owned_equip.has(id):
			continue
		var t := EquipDB.tier_of(id)
		if t < 2:
			continue
		var w: float = [0.0, 0.0, 50.0, 35.0, 15.0][t]
		pool.append([id, w])
		total += w
	if pool.is_empty():
		coins += 150
		save()
		return ""
	var roll := randf() * total
	var picked: String = pool[0][0]
	for entry in pool:
		roll -= float(entry[1])
		if roll <= 0.0:
			picked = entry[0]
			break
	owned_equip.append(picked)
	var slot := EquipDB.slot_of(picked)
	var cur: String = equipped.get(slot, "")
	if cur == "" or EquipDB.tier_of(cur) < EquipDB.tier_of(picked):
		equipped[slot] = picked
	save()
	return picked


# ---------- 關卡與大逃殺紀錄 ----------

func level_total() -> int:
	var sum := 0
	for k in level_best:
		sum += int(level_best[k])
	return sum


func is_level_unlocked(n: int) -> bool:
	return n <= cleared_level + 1


# 回傳首次通關獎勵（沒有則 0）
func record_level(level: int, score: int, won: bool) -> int:
	runs += 1
	var key := str(level)
	level_best[key] = maxi(int(level_best.get(key, 0)), score)
	best_score = maxi(best_score, score)
	var bonus := 0
	if won and level > cleared_level:
		cleared_level = level
		bonus = LevelDB.clear_bonus(level)
		coins += bonus
	save()
	return bonus


func br_place_coins(place: int) -> int:
	if place == 1:
		return 50
	if place <= 3:
		return 20
	if place <= 6:
		return 8
	return 0


# 回傳 {points, coins}
func record_br(place: int, kills: int, total_players: int) -> Dictionary:
	br_games += 1
	br_kills += kills
	if place == 1:
		br_wins += 1
	br_best_place = place if br_best_place == 0 else mini(br_best_place, place)
	var points := (total_players + 1 - place) * 50 + kills * 100 + (500 if place == 1 else 0)
	br_best_points = maxi(br_best_points, points)
	var bonus := br_place_coins(place)
	coins += bonus
	save()
	return {"points": points, "coins": bonus}
