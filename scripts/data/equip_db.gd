extends RefCounted
# 裝備系統：6 個部位、每個部位 4 階。Lv1~3 可用喪屍幣購買，傳說(Lv4)為大逃殺空投限定。

# 屬性鍵：hp 生命、armor 減傷%、speed 移速%、dmg 傷害%、reload 換彈縮短%、ammo 備彈%
const STAT_NAMES: Dictionary = {
	"hp": "生命", "armor": "減傷", "speed": "移速", "dmg": "傷害", "reload": "換彈速度", "ammo": "備彈量",
}
const STAT_UNITS: Dictionary = {
	"hp": "", "armor": "%", "speed": "%", "dmg": "%", "reload": "%", "ammo": "%",
}

const SLOTS: Array = ["head", "body", "legs", "hands", "back", "charm"]
const SLOT_NAMES: Dictionary = {
	"head": "頭盔", "body": "護甲", "legs": "靴子", "hands": "手套", "back": "背包", "charm": "護符",
}

const TIERS: Array = [
	{"name": "普通", "color": Color(0.75, 0.78, 0.82), "cost": 40},
	{"name": "稀有", "color": Color(0.3, 0.6, 1.0), "cost": 120},
	{"name": "史詩", "color": Color(0.75, 0.38, 1.0), "cost": 320},
	{"name": "傳說", "color": Color(1.0, 0.75, 0.2), "cost": 0},   # 0 = 空投限定
]

# 每個部位的主屬性：[Lv1, Lv2, Lv3, Lv4]
const MAIN_STAT: Dictionary = {
	"head": ["armor", [3, 6, 10, 15]],
	"body": ["hp", [15, 30, 55, 90]],
	"legs": ["speed", [3, 6, 9, 14]],
	"hands": ["reload", [8, 15, 22, 32]],
	"back": ["ammo", [15, 30, 50, 80]],
	"charm": ["dmg", [4, 8, 13, 20]],
}
# Lv3、Lv4 額外附帶的副屬性
const BONUS_STAT: Dictionary = {
	"head": ["hp", [0, 0, 10, 25]],
	"body": ["armor", [0, 0, 3, 6]],
	"legs": ["hp", [0, 0, 8, 18]],
	"hands": ["dmg", [0, 0, 3, 6]],
	"back": ["speed", [0, 0, 2, 5]],
	"charm": ["armor", [0, 0, 3, 6]],
}

const NAMES: Dictionary = {
	"head": ["工地安全帽", "戰術頭盔", "防暴頭盔", "王者之冠"],
	"body": ["防刺背心", "戰鬥護甲", "重型裝甲", "不滅聖鎧"],
	"legs": ["運動鞋", "戰術靴", "強化跑靴", "疾風戰靴"],
	"hands": ["工作手套", "戰術手套", "機械手套", "神速護腕"],
	"back": ["帆布背包", "戰術背包", "軍用背包", "無盡彈藥箱"],
	"charm": ["幸運護符", "獵人徽章", "狂戰士圖騰", "毀滅之眼"],
}


static func item_id(slot: String, tier: int) -> String:
	return "%s_%d" % [slot, tier]


static func slot_of(id: String) -> String:
	return id.get_slice("_", 0)


static func tier_of(id: String) -> int:
	return int(id.get_slice("_", 1))


static func exists(id: String) -> bool:
	return SLOTS.has(slot_of(id)) and tier_of(id) >= 1 and tier_of(id) <= 4


static func all_ids() -> Array:
	var out: Array = []
	for s in SLOTS:
		for t in range(1, 5):
			out.append(item_id(s, t))
	return out


static func item_name(id: String) -> String:
	return NAMES[slot_of(id)][tier_of(id) - 1]


static func tier_info(id: String) -> Dictionary:
	return TIERS[tier_of(id) - 1]


static func cost(id: String) -> int:
	return int(tier_info(id)["cost"])


static func airdrop_only(id: String) -> bool:
	return cost(id) <= 0


static func stats(id: String) -> Dictionary:
	var slot := slot_of(id)
	var t := tier_of(id) - 1
	var out: Dictionary = {}
	var main: Array = MAIN_STAT[slot]
	out[main[0]] = (main[1] as Array)[t]
	var bonus: Array = BONUS_STAT[slot]
	var bv: int = (bonus[1] as Array)[t]
	if bv > 0:
		out[bonus[0]] = bv
	return out


static func stats_text(id: String) -> String:
	var parts: PackedStringArray = []
	var st := stats(id)
	for k in st:
		parts.append("%s +%d%s" % [STAT_NAMES[k], st[k], STAT_UNITS[k]])
	return "　".join(parts)


# 已裝備項目的屬性加總
static func totals(equipped: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in STAT_NAMES:
		out[k] = 0.0
	for slot in equipped:
		var id: String = equipped[slot]
		if id == "" or not exists(id):
			continue
		var st := stats(id)
		for k in st:
			out[k] = float(out[k]) + float(st[k])
	out["armor"] = minf(float(out["armor"]), 60.0)
	return out
