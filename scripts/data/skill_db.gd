extends RefCounted
# 技能資料：ZXCVB 五個技能，Lv1~3 升級，滿級後可選擇「突破」進化

const MAX_LEVEL: int = 3
const ORDER: Array = ["shockwave", "heal", "grenade", "freeze", "frenzy"]
const KEYS: Array = [KEY_Z, KEY_X, KEY_C, KEY_V, KEY_B]
const KEY_NAMES: Array = ["Z", "X", "C", "V", "B"]

const SKILLS: Dictionary = {
	"shockwave": {
		"name": "衝擊波", "evo_name": "地裂震撼", "color": Color(1.0, 0.6, 0.2),
		"cd": [14.0, 12.0, 10.0], "evo_cd": 10.0,
		"desc": "震開周圍敵人並造成傷害。",
		"levels": ["範圍 9m　傷害 60", "範圍 11m　傷害 85", "範圍 13m　傷害 110"],
		"evo_desc": "範圍 20m　傷害 260　並使敵人暈眩 2.5 秒",
	},
	"heal": {
		"name": "戰地急救", "evo_name": "再生領域", "color": Color(0.35, 1.0, 0.5),
		"cd": [24.0, 21.0, 18.0], "evo_cd": 22.0,
		"desc": "立刻回復生命值。",
		"levels": ["回復 40 點", "回復 55 點", "回復 70 點"],
		"evo_desc": "回復全部生命，並持續再生 8 點/秒 共 6 秒",
	},
	"grenade": {
		"name": "手榴彈", "evo_name": "集束轟炸", "color": Color(1.0, 0.4, 0.15),
		"cd": [10.0, 9.0, 8.0], "evo_cd": 9.0,
		"desc": "朝準心投擲，延遲後爆炸。",
		"levels": ["半徑 5m　傷害 140", "半徑 6m　傷害 190", "半徑 7m　傷害 240"],
		"evo_desc": "連續 4 次大範圍爆炸　半徑 9m　每次傷害 300",
	},
	"freeze": {
		"name": "寒霜領域", "evo_name": "絕對零度", "color": Color(0.5, 0.85, 1.0),
		"cd": [18.0, 16.0, 14.0], "evo_cd": 16.0,
		"desc": "讓範圍內敵人大幅減速。",
		"levels": ["減速 65%　持續 4 秒", "減速 65%　持續 5 秒", "減速 65%　持續 6 秒"],
		"evo_desc": "範圍 45m 完全冰凍 5 秒，並造成 50 傷害",
	},
	"frenzy": {
		"name": "狂暴", "evo_name": "殺戮時刻", "color": Color(1.0, 0.25, 0.3),
		"cd": [28.0, 25.0, 22.0], "evo_cd": 26.0,
		"desc": "短時間內射速與傷害大幅提升。",
		"levels": ["8 秒　射速 ×1.7　傷害 ×1.4", "10 秒　射速 ×1.7　傷害 ×1.5", "12 秒　射速 ×1.7　傷害 ×1.6"],
		"evo_desc": "14 秒　射速 ×2.5　傷害 ×2.2　無限彈藥",
	},
}


static func display_name(id: String, evolved: bool) -> String:
	var s: Dictionary = SKILLS[id]
	return s["evo_name"] if evolved else s["name"]


static func cooldown(id: String, level: int, evolved: bool) -> float:
	var s: Dictionary = SKILLS[id]
	if evolved:
		return s["evo_cd"]
	return (s["cd"] as Array)[clampi(level, 1, MAX_LEVEL) - 1]


static func level_desc(id: String, level: int, evolved: bool) -> String:
	var s: Dictionary = SKILLS[id]
	if evolved:
		return s["evo_desc"]
	return (s["levels"] as Array)[clampi(level, 1, MAX_LEVEL) - 1]
