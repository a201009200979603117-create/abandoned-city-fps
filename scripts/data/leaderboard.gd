extends RefCounted
# 排行榜：由虛擬玩家組成，每天分數會小幅浮動，讓玩家有競爭感
# 殭屍關卡榜：分數 = 各關最高分總和　大逃殺榜：分數 = 積分（名次+擊殺）

const NAMES: Array = [
	"夜行者", "Ghost_Rider", "殭屍獵人小王", "NightOwl", "鐵血戰士", "Luna", "Viper",
	"末日倖存者", "BlackCat", "阿宏", "Sniper_K", "小雨", "Rex", "鋼鐵老爹",
	"Zed", "月光射手", "Hunter88", "沈默的羔羊", "Mika", "Bravo", "夜鷹", "Kuro", "老陳", "Nova",
]

const ZOMBIE_SCORES: Array = [
	50520, 47760, 45060, 42180, 39480, 36720, 34200, 31560, 29100, 26580, 24240, 21960,
	19740, 17640, 15600, 13680, 11760, 9900, 8280, 6720, 5280, 3960, 2820, 1800,
]

const BR_SCORES: Array = [
	3400, 3150, 2900, 2650, 2400, 2200, 2000, 1800, 1600, 1420, 1250, 1100,
	950, 800, 680, 560, 450, 350, 260, 180, 120, 80, 50, 30,
]


# 回傳由高到低排序的陣列：{name, score, extra, is_player}
# extra：殭屍榜為通關數，大逃殺榜為勝場
static func entries(player_score: int, player_extra: int, mode: String = "zombie") -> Array:
	var base: Array = BR_SCORES if mode == "br" else ZOMBIE_SCORES
	var day := int(Time.get_unix_time_from_system() / 86400.0)
	var jitter := RandomNumberGenerator.new()
	jitter.seed = day + (99 if mode == "br" else 0)
	var order := NAMES.duplicate()
	var shuffler := RandomNumberGenerator.new()
	shuffler.seed = 20240607 + (7 if mode == "br" else 0)
	for i in range(order.size() - 1, 0, -1):
		var j := shuffler.randi_range(0, i)
		var tmp: Variant = order[i]
		order[i] = order[j]
		order[j] = tmp

	var list: Array = []
	for i in base.size():
		var s := int(float(base[i]) * jitter.randf_range(0.94, 1.06))
		var extra := clampi(s / 5200, 0, 10) if mode != "br" else s / 1200
		list.append({"name": order[i], "score": s, "extra": extra, "is_player": false})

	list.append({"name": "你", "score": player_score, "extra": player_extra, "is_player": true})
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["score"] == b["score"]:
			return a["is_player"] and not b["is_player"]
		return a["score"] > b["score"])
	return list


static func rank_of(player_score: int, player_extra: int, mode: String = "zombie") -> int:
	var list := entries(player_score, player_extra, mode)
	for i in list.size():
		if list[i]["is_player"]:
			return i + 1
	return list.size()
