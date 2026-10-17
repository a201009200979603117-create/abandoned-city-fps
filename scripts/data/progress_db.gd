extends RefCounted
# 成長資料：玩家等級 / 經驗值、成就、每日任務範本、槍枝配件

# ---------- 等級 ----------
# 累計經驗 = 50 × L × (L-1)：Lv2 需 100，Lv3 需 300，Lv4 需 600 …
static func level_for(xp: int) -> int:
	return maxi(int((1.0 + sqrt(1.0 + float(xp) / 12.5)) / 2.0), 1)


static func xp_at(level: int) -> int:
	return 50 * level * (level - 1)


static func level_reward(level: int) -> int:
	return 20 + 5 * level


# ---------- 成就 ----------
# stat：累計統計名稱；達到 target 即解鎖，獲得 coins 與 xp
const ACHIEVEMENTS: Array = [
	{"id": "first_blood", "name": "初次見血", "desc": "擊倒第 1 個敵人", "stat": "kills_total", "target": 1, "coins": 10, "xp": 20},
	{"id": "hunter_100", "name": "獵殺者", "desc": "累計擊倒 100 個敵人", "stat": "kills_total", "target": 100, "coins": 40, "xp": 80},
	{"id": "hunter_1000", "name": "屠殺機器", "desc": "累計擊倒 1000 個敵人", "stat": "kills_total", "target": 1000, "coins": 200, "xp": 400},
	{"id": "head_50", "name": "神射手", "desc": "累計爆頭 50 次", "stat": "headshots", "target": 50, "coins": 50, "xp": 100},
	{"id": "head_500", "name": "爆頭大師", "desc": "累計爆頭 500 次", "stat": "headshots", "target": 500, "coins": 250, "xp": 500},
	{"id": "boss_1", "name": "屠龍者", "desc": "擊敗 1 隻 Boss", "stat": "boss_kills", "target": 1, "coins": 60, "xp": 120},
	{"id": "boss_10", "name": "Boss 終結者", "desc": "擊敗 10 隻 Boss", "stat": "boss_kills", "target": 10, "coins": 300, "xp": 600},
	{"id": "wave_50", "name": "堅守者", "desc": "累計撐過 50 波", "stat": "waves", "target": 50, "coins": 60, "xp": 120},
	{"id": "clear_1", "name": "初次通關", "desc": "通關殭屍關卡 1 次", "stat": "zombie_wins", "target": 1, "coins": 30, "xp": 60},
	{"id": "clear_10", "name": "常勝將軍", "desc": "通關殭屍關卡 10 次", "stat": "zombie_wins", "target": 10, "coins": 150, "xp": 300},
	{"id": "br_win_1", "name": "大吉大利", "desc": "大逃殺奪冠 1 次", "stat": "br_wins", "target": 1, "coins": 80, "xp": 150},
	{"id": "br_win_5", "name": "吃雞專業戶", "desc": "大逃殺奪冠 5 次", "stat": "br_wins", "target": 5, "coins": 250, "xp": 500},
	{"id": "br_kill_50", "name": "戰場死神", "desc": "大逃殺累計擊倒 50 名玩家", "stat": "br_kills", "target": 50, "coins": 100, "xp": 200},
	{"id": "br_top3", "name": "常客", "desc": "大逃殺進入前三名 10 次", "stat": "br_top3", "target": 10, "coins": 100, "xp": 200},
	{"id": "grenade_20", "name": "爆破專家", "desc": "用手榴彈或爆炸擊倒 20 個敵人", "stat": "explosive_kills", "target": 20, "coins": 80, "xp": 160},
	{"id": "mission_10", "name": "勤勞玩家", "desc": "完成 10 個每日任務", "stat": "missions_done", "target": 10, "coins": 120, "xp": 240},
	{"id": "level_10", "name": "資深倖存者", "desc": "玩家等級達到 10", "stat": "player_level", "target": 10, "coins": 150, "xp": 0},
	{"id": "skins_all", "name": "收藏家", "desc": "收集全部槍枝皮膚", "stat": "skins_owned", "target": 9, "coins": 200, "xp": 300},
	{"id": "attach_max", "name": "改裝大師", "desc": "把任一配件升到滿級", "stat": "attach_maxed", "target": 1, "coins": 60, "xp": 100},
]


static func achievement(id: String) -> Dictionary:
	for a in ACHIEVEMENTS:
		if a["id"] == id:
			return a
	return {}


# 回傳這次新解鎖的成就 id
static func check_achievements(stats: Dictionary, unlocked: Dictionary) -> Array:
	var out: Array = []
	for a in ACHIEVEMENTS:
		if unlocked.has(a["id"]):
			continue
		if int(stats.get(a["stat"], 0)) >= int(a["target"]):
			out.append(a["id"])
	return out


# ---------- 每日任務 ----------
# stat：對應 Game.record 的統計名稱
const MISSIONS: Array = [
	{"id": "kill_z", "text": "在殭屍關卡擊倒 %d 隻殭屍", "stat": "kills_zombie", "min": 25, "max": 60, "step": 5, "coins": 30, "xp": 40},
	{"id": "head", "text": "爆頭擊中 %d 次", "stat": "headshots", "min": 10, "max": 30, "step": 5, "coins": 35, "xp": 50},
	{"id": "waves", "text": "撐過 %d 波殭屍", "stat": "waves", "min": 4, "max": 8, "step": 1, "coins": 30, "xp": 40},
	{"id": "br_kill", "text": "在大逃殺擊倒 %d 名玩家", "stat": "br_kills", "min": 2, "max": 5, "step": 1, "coins": 45, "xp": 60},
	{"id": "br_play", "text": "完成 %d 場大逃殺", "stat": "br_games", "min": 2, "max": 3, "step": 1, "coins": 30, "xp": 40},
	{"id": "br_top3", "text": "大逃殺進入前三名 %d 次", "stat": "br_top3", "min": 1, "max": 2, "step": 1, "coins": 60, "xp": 80},
	{"id": "boss", "text": "擊敗 %d 隻 Boss", "stat": "boss_kills", "min": 1, "max": 2, "step": 1, "coins": 70, "xp": 90},
	{"id": "explode", "text": "用爆炸擊倒 %d 個敵人", "stat": "explosive_kills", "min": 4, "max": 12, "step": 2, "coins": 40, "xp": 50},
]


# 依日期字串產生當日的 3 個任務（同一天內結果固定）
static func generate(date: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(date)
	var idx: Array = range(MISSIONS.size())
	# 洗牌（以日期為種子）
	for i in range(idx.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = idx[i]
		idx[i] = idx[j]
		idx[j] = tmp
	var list: Array = []
	for k in 3:
		var m: Dictionary = MISSIONS[idx[k]]
		var steps := int((int(m["max"]) - int(m["min"])) / int(m["step"]))
		var target := int(m["min"]) + rng.randi_range(0, steps) * int(m["step"])
		list.append({"id": m["id"], "stat": m["stat"], "text": m["text"] % target, "target": target, "progress": 0,
			"coins": m["coins"], "xp": m["xp"], "claimed": false})
	return list


# ---------- 槍枝配件 ----------
const ATTACH_KINDS: Array = ["grip", "mag", "muzzle", "scope"]
const ATTACH_MAX: int = 3
const ATTACH: Dictionary = {
	"grip": {"name": "垂直握把", "desc": "後座力 -10% / 級", "costs": [80, 200, 420]},
	"mag": {"name": "擴容彈匣", "desc": "彈匣容量 +20% / 級", "costs": [100, 240, 480]},
	"muzzle": {"name": "槍口穩定器", "desc": "散佈 -10% / 級", "costs": [90, 220, 450]},
	"scope": {"name": "瞄準鏡", "desc": "開鏡更準、放大更多", "costs": [120, 260, 520]},
}


static func attach_cost(kind: String, current_level: int) -> int:
	if current_level >= ATTACH_MAX:
		return 0
	return int((ATTACH[kind]["costs"] as Array)[current_level])
