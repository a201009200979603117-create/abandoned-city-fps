extends RefCounted
# 關卡資料：10 個關卡，各有主題外觀、波數與難度。通關後解鎖下一關。

# type_weights：[一般, 跑者, 坦克]，會再依波次調整
const LEVELS: Array = [
	{
		"name": "廢棄街區", "desc": "一切開始的地方。適合熟悉操作。", "seed": 20260301,
		"waves": 5, "count_mult": 0.9, "hp_mult": 0.9, "speed_mult": 0.95, "type_weights": [1.0, 0.5, 0.2], "skip": 0.28,
		"theme": {"sky_top": Color(0.16, 0.17, 0.18), "sky_horizon": Color(0.45, 0.43, 0.39), "fog": Color(0.33, 0.33, 0.32), "fog_density": 0.022, "ambient": Color(0.26, 0.27, 0.29), "ambient_energy": 0.65, "sun": Color(0.78, 0.74, 0.66), "sun_energy": 0.4, "ground": Color(0.2, 0.19, 0.17)},
	},
	{
		"name": "午夜街道", "desc": "夜幕低垂，視野變差。", "seed": 777001,
		"waves": 5, "count_mult": 1.0, "hp_mult": 1.0, "speed_mult": 1.0, "type_weights": [1.0, 0.6, 0.25], "skip": 0.3,
		"theme": {"sky_top": Color(0.015, 0.02, 0.04), "sky_horizon": Color(0.07, 0.09, 0.12), "fog": Color(0.05, 0.065, 0.085), "fog_density": 0.03, "ambient": Color(0.08, 0.1, 0.14), "ambient_energy": 0.7, "sun": Color(0.4, 0.48, 0.62), "sun_energy": 0.22, "ground": Color(0.12, 0.12, 0.13)},
	},
	{
		"name": "赤銹之夜", "desc": "鐵鏽色的煙塵蔽天，殭屍更加狂躁。", "seed": 313371,
		"waves": 6, "count_mult": 1.05, "hp_mult": 1.05, "speed_mult": 1.05, "type_weights": [1.0, 0.8, 0.25], "skip": 0.3,
		"theme": {"sky_top": Color(0.07, 0.03, 0.03), "sky_horizon": Color(0.38, 0.16, 0.1), "fog": Color(0.22, 0.1, 0.08), "fog_density": 0.026, "ambient": Color(0.28, 0.15, 0.12), "ambient_energy": 0.7, "sun": Color(0.85, 0.45, 0.32), "sun_energy": 0.38, "ground": Color(0.17, 0.12, 0.1)},
	},
	{
		"name": "迷霧城區", "desc": "濃霧中，敵人從四面八方撲來。", "seed": 90210,
		"waves": 6, "count_mult": 1.1, "hp_mult": 1.1, "speed_mult": 1.0, "type_weights": [1.0, 0.7, 0.3], "skip": 0.24,
		"theme": {"sky_top": Color(0.34, 0.35, 0.36), "sky_horizon": Color(0.5, 0.51, 0.5), "fog": Color(0.46, 0.47, 0.46), "fog_density": 0.05, "ambient": Color(0.4, 0.41, 0.42), "ambient_energy": 0.85, "sun": Color(0.75, 0.76, 0.76), "sun_energy": 0.3, "ground": Color(0.22, 0.22, 0.21)},
	},
	{
		"name": "黃昏廢墟", "desc": "夕陽下的廢墟，坦克型敵人增加。", "seed": 424242,
		"waves": 7, "count_mult": 1.15, "hp_mult": 1.2, "speed_mult": 1.05, "type_weights": [1.0, 0.7, 0.5], "skip": 0.34,
		"theme": {"sky_top": Color(0.2, 0.17, 0.2), "sky_horizon": Color(0.75, 0.5, 0.3), "fog": Color(0.5, 0.38, 0.28), "fog_density": 0.018, "ambient": Color(0.42, 0.33, 0.28), "ambient_energy": 0.75, "sun": Color(1.0, 0.68, 0.4), "sun_energy": 0.65, "ground": Color(0.22, 0.17, 0.13)},
	},
	{
		"name": "毒霧工業區", "desc": "綠色毒霧籠罩，敵人速度更快。", "seed": 555123,
		"waves": 7, "count_mult": 1.2, "hp_mult": 1.25, "speed_mult": 1.15, "type_weights": [0.9, 1.0, 0.4], "skip": 0.26,
		"theme": {"sky_top": Color(0.1, 0.12, 0.07), "sky_horizon": Color(0.4, 0.44, 0.22), "fog": Color(0.3, 0.34, 0.16), "fog_density": 0.034, "ambient": Color(0.28, 0.32, 0.18), "ambient_energy": 0.75, "sun": Color(0.8, 0.85, 0.5), "sun_energy": 0.33, "ground": Color(0.15, 0.16, 0.1)},
	},
	{
		"name": "核冬落塵", "desc": "灰白的落塵覆蓋一切，大量敵人湧入。", "seed": 868686,
		"waves": 8, "count_mult": 1.3, "hp_mult": 1.35, "speed_mult": 1.1, "type_weights": [1.0, 0.8, 0.5], "skip": 0.3,
		"theme": {"sky_top": Color(0.38, 0.4, 0.42), "sky_horizon": Color(0.6, 0.61, 0.6), "fog": Color(0.55, 0.56, 0.56), "fog_density": 0.04, "ambient": Color(0.5, 0.52, 0.54), "ambient_energy": 0.9, "sun": Color(0.85, 0.86, 0.88), "sun_energy": 0.4, "ground": Color(0.46, 0.47, 0.47)},
	},
	{
		"name": "焚城", "desc": "整座城市陷入大火，敵人又快又硬。", "seed": 666666,
		"waves": 8, "count_mult": 1.35, "hp_mult": 1.5, "speed_mult": 1.2, "type_weights": [0.8, 1.0, 0.7], "skip": 0.32,
		"theme": {"sky_top": Color(0.07, 0.03, 0.02), "sky_horizon": Color(0.65, 0.25, 0.08), "fog": Color(0.32, 0.13, 0.06), "fog_density": 0.03, "ambient": Color(0.4, 0.2, 0.12), "ambient_energy": 0.75, "sun": Color(1.0, 0.5, 0.25), "sun_energy": 0.55, "ground": Color(0.13, 0.09, 0.07)},
	},
	{
		"name": "輻射風暴", "desc": "輻射風暴籠罩的死城，敵人異常強大。", "seed": 424200,
		"waves": 9, "count_mult": 1.45, "hp_mult": 1.7, "speed_mult": 1.2, "type_weights": [0.7, 1.0, 0.9], "skip": 0.27,
		"theme": {"sky_top": Color(0.1, 0.07, 0.12), "sky_horizon": Color(0.42, 0.3, 0.4), "fog": Color(0.26, 0.2, 0.28), "fog_density": 0.032, "ambient": Color(0.3, 0.24, 0.32), "ambient_energy": 0.75, "sun": Color(0.8, 0.65, 0.85), "sun_energy": 0.35, "ground": Color(0.14, 0.12, 0.15)},
	},
	{
		"name": "末日終局", "desc": "最終決戰。撐過 10 波，成為傳說。", "seed": 1999,
		"waves": 10, "count_mult": 1.6, "hp_mult": 2.0, "speed_mult": 1.25, "type_weights": [0.6, 1.0, 1.0], "skip": 0.3,
		"theme": {"sky_top": Color(0.02, 0.01, 0.01), "sky_horizon": Color(0.3, 0.07, 0.04), "fog": Color(0.14, 0.05, 0.04), "fog_density": 0.04, "ambient": Color(0.22, 0.1, 0.08), "ambient_energy": 0.7, "sun": Color(0.9, 0.3, 0.2), "sun_energy": 0.4, "ground": Color(0.1, 0.08, 0.08)},
	},
]

# 大逃殺地圖外觀（黃昏的城市）
const BR_THEME: Dictionary = {
	"sky_top": Color(0.17, 0.16, 0.19), "sky_horizon": Color(0.7, 0.48, 0.32), "fog": Color(0.45, 0.4, 0.37), "fog_density": 0.014,
	"ambient": Color(0.33, 0.31, 0.32), "ambient_energy": 0.8, "sun": Color(1.0, 0.78, 0.55), "sun_energy": 0.7, "ground": Color(0.2, 0.18, 0.16),
}
const BR_SEED: int = 8080
const BR_SKIP: float = 0.3


static func count() -> int:
	return LEVELS.size()


static func get_level(n: int) -> Dictionary:
	return LEVELS[clampi(n, 1, LEVELS.size()) - 1]


# 通關獎勵（第一次通關）
static func clear_bonus(n: int) -> int:
	return 20 * n
