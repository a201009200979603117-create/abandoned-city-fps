extends RefCounted
# 槍枝與皮膚資料表，以及共用的槍枝模型建構函式（遊戲內與選單預覽共用）

# 部件角色：0 槍身　1 槍管　2 握把/槍托　3 配件（彈匣、瞄具）
const RARITY: Dictionary = {
	"common": {"name": "普通", "color": Color(0.75, 0.78, 0.82), "weight": 60.0},
	"rare": {"name": "稀有", "color": Color(0.3, 0.6, 1.0), "weight": 25.0},
	"epic": {"name": "史詩", "color": Color(0.75, 0.38, 1.0), "weight": 11.0},
	"legendary": {"name": "傳說", "color": Color(1.0, 0.75, 0.2), "weight": 4.0},
}

# body/barrel/grip/accent 為四種部件顏色；glow 為自發光強度
const SKINS: Dictionary = {
	"default": {"name": "磨損黑鋼", "rarity": "common", "colors": [Color(0.1, 0.1, 0.1), Color(0.07, 0.07, 0.07), Color(0.14, 0.11, 0.08), Color(0.2, 0.2, 0.2)], "metal": 0.35, "glow": 0.0},
	"desert": {"name": "沙塵迷彩", "rarity": "common", "colors": [Color(0.5, 0.42, 0.28), Color(0.2, 0.18, 0.13), Color(0.36, 0.29, 0.18), Color(0.28, 0.24, 0.16)], "metal": 0.15, "glow": 0.0},
	"forest": {"name": "苔蘚迷彩", "rarity": "common", "colors": [Color(0.18, 0.26, 0.16), Color(0.08, 0.1, 0.07), Color(0.24, 0.19, 0.11), Color(0.13, 0.19, 0.11)], "metal": 0.15, "glow": 0.0},
	"ocean": {"name": "海軍灰藍", "rarity": "rare", "colors": [Color(0.2, 0.26, 0.32), Color(0.09, 0.11, 0.14), Color(0.13, 0.15, 0.18), Color(0.4, 0.46, 0.5)], "metal": 0.55, "glow": 0.0},
	"crimson": {"name": "銹蝕紅", "rarity": "rare", "colors": [Color(0.38, 0.14, 0.08), Color(0.14, 0.06, 0.04), Color(0.2, 0.09, 0.06), Color(0.55, 0.3, 0.12)], "metal": 0.3, "glow": 0.0},
	"arctic": {"name": "灰燼白漆", "rarity": "rare", "colors": [Color(0.66, 0.67, 0.64), Color(0.3, 0.3, 0.29), Color(0.4, 0.4, 0.38), Color(0.5, 0.5, 0.46)], "metal": 0.2, "glow": 0.0},
	"neon": {"name": "輻射警示", "rarity": "epic", "colors": [Color(0.12, 0.12, 0.1), Color(0.07, 0.07, 0.06), Color(0.16, 0.15, 0.1), Color(0.8, 0.7, 0.1)], "metal": 0.4, "glow": 0.35},
	"void": {"name": "焦黑殘燼", "rarity": "epic", "colors": [Color(0.06, 0.05, 0.05), Color(0.03, 0.03, 0.03), Color(0.1, 0.07, 0.06), Color(0.9, 0.35, 0.08)], "metal": 0.5, "glow": 0.5},
	"gold": {"name": "戰前鍍金", "rarity": "legendary", "colors": [Color(0.72, 0.56, 0.2), Color(0.45, 0.33, 0.1), Color(0.3, 0.2, 0.08), Color(0.8, 0.7, 0.4)], "metal": 0.9, "glow": 0.0},
}

# parts：[角色, 尺寸, 位置]
const WEAPONS: Dictionary = {
	"rifle": {
		"name": "AR-47 突擊步槍", "desc": "均衡的全自動步槍，新手首選。",
		"damage": 25.0, "fire_rate": 0.11, "range": 100.0, "mag": 30, "reserve": 120, "reload": 1.5,
		"recoil": 0.012, "pellets": 1, "spread": 0.5, "auto": true, "zoom": 60.0, "flash_z": -0.55,
		"parts": [
			[0, Vector3(0.07, 0.1, 0.45), Vector3(0.0, 0.0, 0.0)],
			[1, Vector3(0.035, 0.035, 0.3), Vector3(0.0, 0.02, -0.35)],
			[2, Vector3(0.06, 0.16, 0.08), Vector3(0.0, -0.12, 0.05)],
			[2, Vector3(0.05, 0.08, 0.1), Vector3(0.0, -0.08, 0.2)],
			[3, Vector3(0.04, 0.14, 0.07), Vector3(0.0, -0.12, -0.08)],
			[3, Vector3(0.03, 0.04, 0.06), Vector3(0.0, 0.075, -0.1)],
		],
	},
	"pistol": {
		"name": "M9 手槍", "desc": "單發精準，每一槍都要算準。",
		"damage": 38.0, "fire_rate": 0.2, "range": 55.0, "mag": 12, "reserve": 96, "reload": 1.0,
		"recoil": 0.015, "pellets": 1, "spread": 0.2, "auto": false, "zoom": 0.0, "flash_z": -0.3,
		"parts": [
			[0, Vector3(0.055, 0.08, 0.26), Vector3(0.0, 0.0, 0.0)],
			[1, Vector3(0.03, 0.03, 0.12), Vector3(0.0, 0.012, -0.18)],
			[2, Vector3(0.05, 0.15, 0.07), Vector3(0.0, -0.11, 0.08)],
			[3, Vector3(0.02, 0.02, 0.03), Vector3(0.0, 0.05, 0.1)],
			[3, Vector3(0.015, 0.02, 0.015), Vector3(0.0, 0.05, -0.1)],
		],
	},
	"shotgun": {
		"name": "SG-12 霰彈槍", "desc": "近距離一發八彈，轟開殭屍群。",
		"damage": 15.0, "fire_rate": 0.85, "range": 30.0, "mag": 6, "reserve": 42, "reload": 2.2,
		"recoil": 0.04, "pellets": 8, "spread": 4.2, "auto": false, "zoom": 0.0, "flash_z": -0.72,
		"parts": [
			[0, Vector3(0.07, 0.09, 0.4), Vector3(0.0, 0.0, 0.0)],
			[1, Vector3(0.045, 0.045, 0.55), Vector3(0.0, 0.03, -0.4)],
			[3, Vector3(0.08, 0.06, 0.18), Vector3(0.0, -0.02, -0.3)],
			[2, Vector3(0.06, 0.1, 0.25), Vector3(0.0, -0.04, 0.3)],
			[2, Vector3(0.05, 0.13, 0.07), Vector3(0.0, -0.11, 0.1)],
			[1, Vector3(0.02, 0.02, 0.5), Vector3(0.0, -0.03, -0.4)],
		],
	},
	"smg": {
		"name": "MP-7 衝鋒槍", "desc": "超高射速，近中距離壓制利器。",
		"damage": 16.0, "fire_rate": 0.065, "range": 55.0, "mag": 40, "reserve": 200, "reload": 1.6,
		"recoil": 0.008, "pellets": 1, "spread": 1.4, "auto": true, "zoom": 0.0, "flash_z": -0.42,
		"parts": [
			[0, Vector3(0.065, 0.1, 0.32), Vector3(0.0, 0.0, 0.0)],
			[1, Vector3(0.03, 0.03, 0.18), Vector3(0.0, 0.015, -0.25)],
			[3, Vector3(0.035, 0.2, 0.05), Vector3(0.0, -0.15, -0.02)],
			[2, Vector3(0.05, 0.14, 0.07), Vector3(0.0, -0.11, 0.1)],
			[2, Vector3(0.03, 0.05, 0.18), Vector3(0.0, -0.01, 0.25)],
			[3, Vector3(0.025, 0.03, 0.05), Vector3(0.0, 0.065, -0.05)],
		],
	},
	"sniper": {
		"name": "AWM 狙擊槍", "desc": "一發重擊，按住右鍵開鏡。",
		"damage": 160.0, "fire_rate": 1.1, "range": 300.0, "mag": 5, "reserve": 35, "reload": 2.4,
		"recoil": 0.05, "pellets": 1, "spread": 0.0, "auto": false, "zoom": 22.0, "flash_z": -0.9,
		"parts": [
			[0, Vector3(0.06, 0.1, 0.55), Vector3(0.0, 0.0, 0.0)],
			[1, Vector3(0.028, 0.028, 0.6), Vector3(0.0, 0.025, -0.55)],
			[3, Vector3(0.045, 0.045, 0.22), Vector3(0.0, 0.105, -0.05)],
			[3, Vector3(0.02, 0.04, 0.02), Vector3(0.0, 0.07, -0.1)],
			[3, Vector3(0.02, 0.04, 0.02), Vector3(0.0, 0.07, 0.02)],
			[2, Vector3(0.06, 0.12, 0.3), Vector3(0.0, -0.04, 0.38)],
			[2, Vector3(0.05, 0.12, 0.07), Vector3(0.0, -0.11, 0.1)],
		],
	},
	"lmg": {
		"name": "M60 輕機槍", "desc": "超大彈鼓，持續火力無人能敵。",
		"damage": 28.0, "fire_rate": 0.09, "range": 90.0, "mag": 100, "reserve": 200, "reload": 3.4,
		"recoil": 0.018, "pellets": 1, "spread": 2.2, "auto": true, "zoom": 0.0, "flash_z": -0.7,
		"parts": [
			[0, Vector3(0.09, 0.12, 0.5), Vector3(0.0, 0.0, 0.0)],
			[1, Vector3(0.04, 0.04, 0.35), Vector3(0.0, 0.03, -0.45)],
			[3, Vector3(0.12, 0.14, 0.14), Vector3(0.0, -0.12, 0.0)],
			[2, Vector3(0.05, 0.14, 0.07), Vector3(0.0, -0.13, 0.15)],
			[2, Vector3(0.07, 0.1, 0.2), Vector3(0.0, -0.02, 0.3)],
			[3, Vector3(0.015, 0.14, 0.015), Vector3(-0.04, -0.1, -0.5)],
			[3, Vector3(0.015, 0.14, 0.015), Vector3(0.04, -0.1, -0.5)],
		],
	},
}

const ORDER: Array = ["rifle", "pistol", "shotgun", "smg", "sniper", "lmg"]


static func skin_color(skin_id: String) -> Color:
	var skin: Dictionary = SKINS.get(skin_id, SKINS["default"])
	return (skin["colors"] as Array)[0]


# 在 parent 底下建立槍枝模型，回傳 flash_z（槍口位置）
static func build_model(parent: Node3D, weapon_id: String, skin_id: String) -> float:
	var def: Dictionary = WEAPONS.get(weapon_id, WEAPONS["rifle"])
	var skin: Dictionary = SKINS.get(skin_id, SKINS["default"])
	var colors: Array = skin["colors"]
	var mats: Array = []
	for i in 4:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = colors[i]
		mat.roughness = 0.55 - 0.3 * float(skin["metal"])
		mat.metallic = skin["metal"]
		if float(skin["glow"]) > 0.0:
			mat.emission_enabled = true
			mat.emission = colors[3] if i != 1 else colors[1]
			mat.emission_energy_multiplier = skin["glow"] * (1.0 if i >= 1 else 0.25)
		mats.append(mat)
	for part in def["parts"]:
		var m := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = part[1]
		m.mesh = box
		m.material_override = mats[part[0]]
		m.position = part[2]
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(m)
	return def["flash_z"]
