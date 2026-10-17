extends Node3D
# 大逃殺管理：生成 AI 玩家與地上槍枝、安全區縮圈、淘汰與名次、奪冠後的空投

const BotScript = preload("res://scripts/br/br_bot.gd")
const AirdropScript = preload("res://scripts/br/airdrop.gd")
const WeaponDB = preload("res://scripts/data/weapon_db.gd")
const EquipDB = preload("res://scripts/data/equip_db.gd")
const Leaderboard = preload("res://scripts/data/leaderboard.gd")
const PICKUP_SCENE: PackedScene = preload("res://scenes/props/Pickup.tscn")

const HALF: float = 100.0
const BOT_COUNT: int = 11
const ZONE_RADII: Array = [110.0, 70.0, 45.0, 26.0, 12.0, 4.0]
const HOLD_TIME: Array = [35.0, 30.0, 25.0, 20.0, 15.0]
const SHRINK_TIME: Array = [25.0, 22.0, 20.0, 18.0, 15.0]
const FINAL_TIMEOUT: float = 45.0   # 最終圈持續超過這個秒數仍沒分出勝負 → 剩餘 AI 受傷害
const SUDDEN_DPS: float = 15.0
const ZONE_DPS: Array = [1.5, 2.5, 4.0, 7.0, 11.0]
const GUN_WEIGHTS: Dictionary = {"pistol": 22.0, "smg": 18.0, "rifle": 18.0, "shotgun": 14.0, "lmg": 8.0, "sniper": 8.0}
const SHIRTS: Array = [
	Color(0.8, 0.25, 0.2), Color(0.2, 0.45, 0.85), Color(0.25, 0.7, 0.35), Color(0.9, 0.7, 0.2),
	Color(0.7, 0.3, 0.8), Color(0.2, 0.75, 0.75), Color(0.9, 0.5, 0.2), Color(0.85, 0.85, 0.9),
]

var player: CharacterBody3D
var weapon: Node3D
var hint_label: Label
var hint_owned: bool = false
var bots: Array = []
var started: bool = false
var victory: bool = false
var final_time: float = 0.0          # 最終安全區已持續秒數
var sudden_death: bool = false
var drop_watch: Dictionary = {}      # AI 跳傘時間（保底用）
var idle_watch: Dictionary = {}      # AI 原地不動時間（保底用）

# 安全區
var zone_center: Vector3 = Vector3.ZERO
var zone_radius: float = 110.0
var next_center: Vector3 = Vector3.ZERO
var next_radius: float = 110.0
var start_center: Vector3 = Vector3.ZERO
var start_radius: float = 110.0
var phase: int = 0
var shrinking: bool = false
var stage_time: float = 35.0
var stage_total: float = 35.0
var zone_finished: bool = false
var zone_tick: float = 1.0
var zone_mesh: MeshInstance3D

var airdrop: Node3D = null

# 跳傘 / 補給箱 / 道具
var landed: bool = false
var gun_templates: Dictionary = {}     # 槍枝 id -> 模板模型（資源共用，複製出來的實例不再各自建立材質 / 網格）
var item_templates: Dictionary = {}
var spin_t: float = 0.0
var dive_wait: float = 0.0
var match_time: float = 0.0
var supply_drops: Array = []
var supply_schedule: Array = [50.0, 125.0]
var supply_i: int = 0
var last_beep: int = -1
const ITEM_NAMES: Dictionary = {"grenade": "手榴彈", "medkit": "醫療包", "plate": "護甲板"}
var airdrop_land_time: float = 0.0
var airdrop_opened: bool = false


func _exit_tree() -> void:
	# 模板模型不在場景樹內，需手動釋放，否則每場大逃殺都會洩漏
	for t in gun_templates.values():
		if is_instance_valid(t):
			(t as Node).free()
	gun_templates.clear()


func _ready() -> void:
	if not Game.is_br() or not Game.gameplay_boot:
		set_process(false)
		return
	_start_match.call_deferred()


func _start_match() -> void:
	# 等地圖分幀建構完成、且 HUD 已開局（物理恢復運作）
	while not Game.level_ready or Game.state == Game.State.MENU:
		await get_tree().process_frame
	# 等地圖碰撞體註冊進物理空間
	await get_tree().physics_frame
	await get_tree().physics_frame

	player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	weapon = player.get_node_or_null("Head/Camera3D/Weapon") as Node3D
	hint_label = get_node_or_null("/root/Main/UI/PickupHint") as Label
	player.add_to_group("combatants")
	Game.br_alive = Game.BR_PLAYERS

	# 玩家從高空跳傘：起跳點偏離預定落點 30~45 公尺，可自行操控飛往想去的地方
	var spawn := ground_point(Vector3.ZERO, 25.0, 85.0)
	var off := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized() * randf_range(30.0, 45.0)
	player.global_position = Vector3(clampf(spawn.x + off.x, -HALF + 6.0, HALF - 6.0), 240.0, clampf(spawn.z + off.z, -HALF + 6.0, HALF - 6.0))
	player.rotation.y = atan2(off.x, off.z)
	player.get_node("Head").rotation.x = -0.45
	player.start_skydive()
	player.landed.connect(_on_player_landed)

	# 近身補給：開局附近有幾把槍
	for i in 3:
		spawn_gun(_random_gun(), ground_point(spawn, 4.0, 12.0))

	# 分幀生成（每個 AI / 每批道具之間讓出一幀），避免網頁 / 手機在開局瞬間卡住
	await _spawn_bots(spawn)
	await _spawn_loot()
	_build_zone()
	_begin_hold()
	started = true
	Game.banner.emit("跳傘中！按跳躍鍵開傘，落地後撿槍、活到最後")


func ground_point(center: Vector3, rmin: float, rmax: float) -> Vector3:
	var space := get_world_3d().direct_space_state
	var p := center
	for i in 40:
		var a := randf() * TAU
		var r := randf_range(rmin, rmax)
		p = center + Vector3(cos(a) * r, 0.0, sin(a) * r)
		p.x = clampf(p.x, -HALF + 4.0, HALF - 4.0)
		p.z = clampf(p.z, -HALF + 4.0, HALF - 4.0)
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 40.0, p.z), Vector3(p.x, -1.0, p.z))
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and hit["position"].y < 0.3:
			return Vector3(p.x, 0.05, p.z)
	return Vector3(p.x, 0.05, p.z)


func _random_gun() -> String:
	var total := 0.0
	for k in GUN_WEIGHTS:
		total += GUN_WEIGHTS[k]
	var roll := randf() * total
	for k in GUN_WEIGHTS:
		roll -= GUN_WEIGHTS[k]
		if roll <= 0.0:
			return k
	return "pistol"


func _spawn_bots(player_pos: Vector3) -> void:
	var names: Array = Leaderboard.NAMES.duplicate()
	names.shuffle()
	for i in BOT_COUNT:
		var bot: CharacterBody3D = BotScript.new()
		var pos := Vector3.ZERO
		for t in 20:
			pos = ground_point(Vector3.ZERO, 25.0, 92.0)
			if pos.distance_to(player_pos) > 30.0:
				break
		bot.bot_name = names[i % names.size()]
		bot.manager = self
		bot.skill = randf_range(0.75, 1.15)
		bot.max_health = randf_range(100.0, 125.0)
		bot.armor = randf_range(0.0, 0.15)
		bot.shirt_color = SHIRTS[i % SHIRTS.size()]
		bot.rotation.y = randf() * TAU
		bot.grenades = 1 if randf() < 0.3 else 0
		bot.medkits = 1 if randf() < 0.5 else 0
		bot.plates = 1 if randf() < 0.4 else 0
		add_child(bot)
		bot.global_position = pos
		bot.start_drop(randf_range(150.0, 260.0))
		bots.append(bot)
		await get_tree().process_frame
		# 每個 AI 出生點附近放兩把槍
		for j in 2:
			spawn_gun(_random_gun(), ground_point(pos, 3.0, 9.0))


func _spawn_loot() -> void:
	for i in 30:
		spawn_gun(_random_gun(), ground_point(Vector3.ZERO, 0.0, 95.0))
		if i % 6 == 5:
			await get_tree().process_frame
	for i in 14:
		spawn_item("grenade", ground_point(Vector3.ZERO, 0.0, 95.0))
	await get_tree().process_frame
	for i in 15:
		spawn_item("medkit", ground_point(Vector3.ZERO, 0.0, 95.0))
	await get_tree().process_frame
	for i in 16:
		spawn_item("plate", ground_point(Vector3.ZERO, 0.0, 95.0))
	await get_tree().process_frame
	for i in 22:
		var pk := PICKUP_SCENE.instantiate()
		pk.set("pickup_type", i % 2)
		var gp := ground_point(Vector3.ZERO, 0.0, 95.0)
		pk.position = Vector3(gp.x, 1.0, gp.z)
		add_child(pk)


# ---------- 道具（手榴彈 / 醫療包 / 護甲板） ----------

func spawn_item(kind: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = Vector3(pos.x, 0.0, pos.z)
	n.set_meta("item_kind", kind)
	n.add_to_group("item_pickups")
	var model := Node3D.new()
	model.position = Vector3(0.0, 0.8, 0.0)
	n.add_child(model)
	var col := Color(0.4, 0.8, 0.4)
	var mat := StandardMaterial3D.new()
	match kind:
		"grenade":
			col = Color(0.45, 0.85, 0.35)
			var mi := MeshInstance3D.new()
			var sph := SphereMesh.new()
			sph.radius = 0.17
			sph.height = 0.34
			mi.mesh = sph
			mat.albedo_color = Color(0.18, 0.28, 0.14)
			mi.material_override = mat
			model.add_child(mi)
			var top := MeshInstance3D.new()
			var bx := BoxMesh.new()
			bx.size = Vector3(0.06, 0.1, 0.06)
			top.mesh = bx
			top.position = Vector3(0, 0.2, 0)
			var tm := StandardMaterial3D.new()
			tm.albedo_color = Color(0.7, 0.7, 0.72)
			top.material_override = tm
			model.add_child(top)
		"medkit":
			col = Color(1.0, 0.45, 0.4)
			var box := MeshInstance3D.new()
			var bx2 := BoxMesh.new()
			bx2.size = Vector3(0.4, 0.26, 0.3)
			box.mesh = bx2
			mat.albedo_color = Color(0.92, 0.92, 0.94)
			box.material_override = mat
			model.add_child(box)
			var cm := StandardMaterial3D.new()
			cm.albedo_color = Color(0.85, 0.1, 0.1)
			cm.emission_enabled = true
			cm.emission = Color(0.85, 0.1, 0.1)
			cm.emission_energy_multiplier = 0.6
			for sz in [Vector3(0.22, 0.02, 0.07), Vector3(0.07, 0.02, 0.22)]:
				var cross := MeshInstance3D.new()
				var cb := BoxMesh.new()
				cb.size = sz
				cross.mesh = cb
				cross.position = Vector3(0, 0.14, 0)
				cross.material_override = cm
				model.add_child(cross)
		"plate":
			col = Color(0.45, 0.7, 1.0)
			var pl := MeshInstance3D.new()
			var pb := BoxMesh.new()
			pb.size = Vector3(0.42, 0.06, 0.34)
			pl.mesh = pb
			mat.albedo_color = Color(0.3, 0.42, 0.62)
			mat.metallic = 0.7
			mat.roughness = 0.35
			mat.emission_enabled = true
			mat.emission = Color(0.3, 0.55, 1.0)
			mat.emission_energy_multiplier = 0.5
			pl.material_override = mat
			pl.rotation.x = 0.35
			model.add_child(pl)
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.55
	cyl.bottom_radius = 0.55
	cyl.height = 0.03
	disc.mesh = cyl
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(col.r, col.g, col.b, 0.5)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc.material_override = dm
	disc.position = Vector3(0.0, 0.03, 0.0)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(disc)
	var label := Label3D.new()
	label.text = str(ITEM_NAMES[kind])
	label.font_size = 30
	label.pixel_size = 0.006
	label.outline_size = 8
	label.modulate = col
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0.0, 1.45, 0.0)
	label.visibility_range_end = 20.0
	n.add_child(label)
	add_child(n)
	return n


func nearest_item(pos: Vector3, max_dist: float) -> Node3D:
	var best: Node3D = null
	var best_d := max_dist
	for g in get_tree().get_nodes_in_group("item_pickups"):
		var n := g as Node3D
		if n == null or n.is_queued_for_deletion():
			continue
		var d := Vector2(n.global_position.x - pos.x, n.global_position.z - pos.z).length()
		if d < best_d:
			best_d = d
			best = n
	return best


# 已著陸且尚未開啟的補給箱
func nearest_supply(pos: Vector3, max_dist: float) -> Node3D:
	var best: Node3D = null
	var best_d := max_dist
	for d_node in supply_drops:
		if not is_instance_valid(d_node):
			continue
		var d3 := d_node as Node3D
		if not d3.call("is_landed"):
			continue
		var d := Vector2(d3.global_position.x - pos.x, d3.global_position.z - pos.z).length()
		if d < best_d:
			best_d = d
			best = d3
	return best


# 槍聲 / 爆炸 / 腳步：半徑內的 AI 會轉頭查看（不會直接鎖定）
func noise(pos: Vector3, radius: float, source: Node) -> void:
	for b in bots:
		if not is_instance_valid(b) or bool(b.get("is_dead")):
			continue
		if (b as Node3D).global_position.distance_to(pos) <= radius:
			b.hear(pos, source)


# ---------- 補給箱空投 ----------

func _spawn_supply() -> void:
	var c := ground_point(zone_center, 0.0, maxf(zone_radius * 0.7, 2.0))
	var d := AirdropScript.new()
	add_child(d)
	d.global_position = Vector3(c.x, 75.0, c.z)
	d.set_meta("supply", true)
	supply_drops.append(d)
	d.opened.connect(_on_supply_opened.bind(d))
	d.landed.connect(func() -> void: Game.banner.emit("補給箱降落！快去搶（小地圖橘色標記）"))
	Game.banner.emit("補給箱空投中！小地圖上有標記")


func _on_supply_opened(d: Node3D) -> void:
	var p := d.global_position
	for i in 2:
		spawn_gun(["rifle", "lmg", "sniper", "smg"].pick_random(), p + Vector3(randf_range(-2.5, 2.5), 0, randf_range(-2.5, 2.5)))
	for kind in ["medkit", "medkit", "plate", "plate", "grenade", "grenade"]:
		spawn_item(kind, p + Vector3(randf_range(-2.8, 2.8), 0, randf_range(-2.8, 2.8)))
	Game.banner.emit("補給箱已開啟！")


# ---------- 跳傘 ----------

func _on_player_landed() -> void:
	if landed:
		return
	landed = true
	Game.banner.emit("安全著陸！撿槍、活到最後")


func diving() -> bool:
	return started and not landed and bool(player.get("skydiving"))


func dive_text() -> String:
	var alt := int(maxf(player.global_position.y, 0.0))
	var chute: bool = bool(player.get("chute_open"))
	return "跳傘中　高度 %d 公尺　%s" % [alt, "降落傘已開啟" if chute else "按跳躍鍵開傘（低於 50 公尺自動開傘）"]


# ---------- 地上槍枝 ----------

func spawn_gun(id: String, pos: Vector3, ammo: int = -1, reserve: int = -1) -> Node3D:
	var def: Dictionary = WeaponDB.WEAPONS[id]
	var n := Node3D.new()
	n.position = Vector3(pos.x, 0.0, pos.z)
	n.set_meta("gun_id", id)
	n.set_meta("gun_ammo", ammo)
	n.set_meta("gun_reserve", reserve)
	n.add_to_group("gun_pickups")

	if not gun_templates.has(id):
		var tpl := Node3D.new()
		tpl.position = Vector3(0.0, 0.9, 0.0)
		tpl.scale = Vector3.ONE * 1.8
		WeaponDB.build_model(tpl, id, "default")
		gun_templates[id] = tpl
	var model: Node3D = (gun_templates[id] as Node3D).duplicate()
	n.add_child(model)

	var rarity_col := Color(0.85, 0.85, 0.9)
	match id:
		"rifle", "shotgun":
			rarity_col = Color(0.35, 0.65, 1.0)
		"lmg":
			rarity_col = Color(0.78, 0.4, 1.0)
		"sniper":
			rarity_col = Color(1.0, 0.78, 0.25)
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.7
	cyl.bottom_radius = 0.7
	cyl.height = 0.03
	disc.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(rarity_col.r, rarity_col.g, rarity_col.b, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc.material_override = mat
	disc.position = Vector3(0.0, 0.03, 0.0)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(disc)

	var label := Label3D.new()
	label.text = str(def["name"])
	label.font_size = 34
	label.pixel_size = 0.006
	label.outline_size = 8
	label.modulate = rarity_col
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0.0, 1.7, 0.0)
	label.visibility_range_end = 24.0
	n.add_child(label)

	add_child(n)
	return n


func nearest_gun(pos: Vector3, max_dist: float) -> Node3D:
	var best: Node3D = null
	var best_d := max_dist
	for g in get_tree().get_nodes_in_group("gun_pickups"):
		var n := g as Node3D
		if n == null or n.is_queued_for_deletion():
			continue
		var d := Vector2(n.global_position.x - pos.x, n.global_position.z - pos.z).length()
		if d < best_d:
			best_d = d
			best = n
	return best


func bot_try_pickup(bot: CharacterBody3D) -> void:
	if bot.dropping:
		return
	var item := nearest_item(bot.global_position, 2.4)
	if item != null and bot.wants_item(str(item.get_meta("item_kind"))):
		bot.give_item(str(item.get_meta("item_kind")))
		item.remove_from_group("item_pickups")
		item.queue_free()
		return
	var sup := nearest_supply(bot.global_position, 3.0)
	if sup != null:
		sup.call("open")
		return
	var gun := nearest_gun(bot.global_position, 2.4)
	if gun == null:
		return
	var id: String = gun.get_meta("gun_id")
	var def: Dictionary = WeaponDB.WEAPONS[id]
	if bot.has_weapon() and bot.weapon_value(id) <= bot.weapon_value(bot.weapon_id) + 15.0:
		return
	if bot.has_weapon():
		spawn_gun(bot.weapon_id, bot.global_position + Vector3(1.0, 0.0, 0.0), bot.ammo, bot.reserve)
	var ammo: int = gun.get_meta("gun_ammo")
	var reserve: int = gun.get_meta("gun_reserve")
	bot.give_weapon(id, int(def["mag"]) if ammo < 0 else ammo, int(float(def["reserve"]) * 0.7) if reserve < 0 else reserve)
	gun.remove_from_group("gun_pickups")
	gun.queue_free()


# ---------- 安全區 ----------

func _build_zone() -> void:
	zone_mesh = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 70.0
	cyl.radial_segments = 64
	cyl.cap_top = false
	cyl.cap_bottom = false
	zone_mesh.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.55, 1.0, 0.22)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	zone_mesh.material_override = mat
	zone_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(zone_mesh)
	_update_zone_mesh()


func _update_zone_mesh() -> void:
	zone_mesh.position = Vector3(zone_center.x, 35.0, zone_center.z)
	zone_mesh.scale = Vector3(zone_radius, 1.0, zone_radius)
	zone_mesh.visible = zone_radius < HALF * 1.35


func _begin_hold() -> void:
	shrinking = false
	start_center = zone_center
	start_radius = zone_radius
	next_radius = ZONE_RADII[phase + 1]
	var off_max := maxf(zone_radius - next_radius, 0.0)
	var a := randf() * TAU
	var r := randf() * off_max
	next_center = zone_center + Vector3(cos(a) * r, 0.0, sin(a) * r)
	next_center.x = clampf(next_center.x, -HALF + next_radius, HALF - next_radius)
	next_center.z = clampf(next_center.z, -HALF + next_radius, HALF - next_radius)
	stage_total = HOLD_TIME[phase]
	stage_time = stage_total


func _update_zone(delta: float) -> void:
	if zone_finished:
		return
	stage_time -= delta
	if shrinking:
		var t := 1.0 - clampf(stage_time / stage_total, 0.0, 1.0)
		zone_radius = lerpf(start_radius, next_radius, t)
		zone_center = start_center.lerp(next_center, t)
		_update_zone_mesh()
		if stage_time <= 0.0:
			phase += 1
			if phase >= ZONE_RADII.size() - 1:
				zone_finished = true
				zone_radius = next_radius
				zone_center = next_center
				_update_zone_mesh()
			else:
				_begin_hold()
	elif stage_time <= 0.0:
		shrinking = true
		stage_total = SHRINK_TIME[phase]
		stage_time = stage_total
		last_beep = -1
		Sfx.play("siren", -4.0)
		Game.banner.emit("安全區開始縮小！")
	else:
		# 縮圈前 5 秒倒數嗶聲
		var sec := int(ceil(stage_time))
		if sec <= 5 and sec != last_beep:
			last_beep = sec
			Sfx.play("beep", -6.0, 1.0 + 0.08 * float(5 - sec))


func zone_text() -> String:
	if zone_finished:
		return "最終安全區"
	var secs := int(ceil(maxf(stage_time, 0.0)))
	if shrinking:
		return "安全區縮小中　%d 秒" % secs
	return "下次縮圈　%d 秒" % secs


func zone_dps() -> float:
	return ZONE_DPS[mini(phase, ZONE_DPS.size() - 1)]


func _outside(n: Node3D) -> bool:
	return Vector2(n.global_position.x - zone_center.x, n.global_position.z - zone_center.z).length() > zone_radius


func _zone_damage() -> void:
	var dps := zone_dps()
	if _outside(player) and not player.is_dead:
		player.take_damage(dps)
	bots = bots.filter(func(b: Variant) -> bool: return is_instance_valid(b))
	if zone_finished:
		final_time += 1.0
	for b in bots:
		var bot := b as CharacterBody3D
		if bool(bot.get("is_dead")):
			continue
		_bot_watchdog(bot)
		if bool(bot.get("is_dead")):
			continue
		if _outside(bot):
			bot.take_damage(dps, null)
	# 決賽圈超時保底：AI 若卡在無法抵達的地方，玩家永遠無法結束比賽 → 剩餘 AI 持續受到毒圈侵蝕
	if zone_finished and final_time >= FINAL_TIMEOUT and not victory:
		if not sudden_death:
			sudden_death = true
			Game.banner.emit("決賽圈超時！剩餘敵人受到毒圈侵蝕")
		for b in bots:
			if not bool(b.get("is_dead")):
				b.take_damage(SUDDEN_DPS, null)


# AI 卡住保底：掉出地圖、跳傘卡住、長時間原地不動 → 強制處理，避免存活數永遠扣不掉
func _bot_watchdog(bot: CharacterBody3D) -> void:
	var id := bot.get_instance_id()
	var pos := bot.global_position
	if pos.y < -10.0 or absf(pos.x) > HALF + 30.0 or absf(pos.z) > HALF + 30.0:
		bot.set("dropping", false)
		bot.die()
		return
	if bool(bot.get("dropping")):
		var dt: float = float(drop_watch.get(id, 0.0)) + 1.0
		drop_watch[id] = dt
		if dt > 45.0:
			bot.force_land(ground_point(Vector3(pos.x, 0.0, pos.z), 0.0, 6.0))
			drop_watch.erase(id)
		return
	var rec: Array = idle_watch.get(id, [pos, 0.0])
	var moved := Vector2(pos.x - (rec[0] as Vector3).x, pos.z - (rec[0] as Vector3).z).length()
	if moved > 1.5 or float(bot.get("heal_t")) > 0.0:
		idle_watch[id] = [pos, 0.0]
		return
	rec[1] = float(rec[1]) + 1.0
	idle_watch[id] = rec
	# 原地不動超過 40 秒：搬到安全區內的空地（不在玩家視線附近時才搬）
	if float(rec[1]) > 40.0 and pos.distance_to(player.global_position) > 25.0:
		var np := ground_point(zone_center, 0.0, maxf(zone_radius * 0.8, 2.0))
		bot.global_position = np
		bot.velocity = Vector3.ZERO
		bot.set("has_goal", false)
		idle_watch[id] = [np, 0.0]


# ---------- 淘汰、勝利 ----------

func bot_died(bot: CharacterBody3D, killer: Node) -> void:
	Game.br_alive = maxi(Game.br_alive - 1, 0)
	var who: String = bot.bot_name
	if killer == player:
		Game.add_br_kill()
		Game.kill_feed.emit("你 擊殺了 %s" % who)
	elif killer != null and killer.get("bot_name") != null:
		Game.kill_feed.emit("%s 擊殺了 %s" % [killer.get("bot_name"), who])
	else:
		Game.kill_feed.emit("%s 被安全區淘汰" % who)
	if bot.has_weapon():
		spawn_gun(bot.weapon_id, bot.global_position, bot.ammo, bot.reserve)
	for kind in ["grenade", "medkit", "plate"]:
		var n: int = int(bot.get(kind + "s"))
		for i in n:
			spawn_item(kind, bot.global_position + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5)))
	if Game.br_alive <= 1 and not player.is_dead and not victory:
		_victory()


func _victory() -> void:
	victory = true
	Game.victory_pending = true
	Game.banner.emit("你是最後的倖存者！空投正在降落…")
	airdrop = AirdropScript.new()
	add_child(airdrop)
	airdrop.global_position = Vector3(0.0, 75.0, 0.0)
	var spot := ground_point(player.global_position, 7.0, 12.0)
	airdrop.global_position = Vector3(spot.x, 75.0, spot.z)
	airdrop.landed.connect(func() -> void: Game.banner.emit("空投已著陸！靠近並%s開啟" % Save.interact_hint()))
	airdrop.opened.connect(_on_airdrop_opened)


func _on_airdrop_opened() -> void:
	airdrop_opened = true
	var item := Save.grant_airdrop()
	Game.airdrop_item = item
	if item != "":
		var tier: Dictionary = EquipDB.tier_info(item)
		Game.banner.emit("空投開啟！獲得【%s】%s" % [tier["name"], EquipDB.item_name(item)])
	else:
		Game.banner.emit("空投開啟！裝備已全收集，獲得 150 喪屍幣")
	get_tree().create_timer(3.2).timeout.connect(func() -> void:
		if Game.is_playing():
			Game.win())


# ---------- 每幀 ----------

func _process(delta: float) -> void:
	if not started or not Game.is_playing() or player == null:
		return

	# 槍枝旋轉
	# 地上道具的旋轉：每 3 幀更新一次，且只處理玩家 45 公尺內的（遠處看不到）
	spin_t += delta
	if Engine.get_physics_frames() % 3 == 0:
		var ppos := player.global_position
		for g in get_tree().get_nodes_in_group("gun_pickups"):
			if (g as Node3D).global_position.distance_squared_to(ppos) < 2025.0:
				((g as Node3D).get_child(0) as Node3D).rotate_y(spin_t * 1.4)
		for g in get_tree().get_nodes_in_group("item_pickups"):
			if (g as Node3D).global_position.distance_squared_to(ppos) < 2025.0:
				((g as Node3D).get_child(0) as Node3D).rotate_y(spin_t * 1.8)
		spin_t = 0.0

	# 玩家著陸（或 35 秒保底）後才開始計時縮圈與補給
	if not landed:
		dive_wait += delta
		if dive_wait > 35.0:
			landed = true
		return
	match_time += delta
	if supply_i < supply_schedule.size() and match_time >= float(supply_schedule[supply_i]) and not victory:
		supply_i += 1
		_spawn_supply()

	if not victory:
		_update_zone(delta)
		zone_tick -= delta
		if zone_tick <= 0.0:
			zone_tick = 1.0
			_zone_damage()
		_player_loot()
	else:
		_airdrop_logic(delta)


func _player_loot() -> void:
	if player.is_dead or bool(player.get("skydiving")):
		return
	var gun := nearest_gun(player.global_position, 2.8)
	var item := nearest_item(player.global_position, 2.6)
	var sup := nearest_supply(player.global_position, 3.8)
	# 補給箱 > 道具 > 槍枝（同時靠近多個時優先處理最重要的）
	if sup != null:
		if hint_label != null:
			hint_label.text = "%s開啟補給箱" % Save.interact_hint()
			hint_label.visible = true
			hint_owned = true
		if Input.is_action_just_pressed("interact"):
			sup.call("open")
		return
	if item != null and (gun == null or Vector2(item.global_position.x - player.global_position.x, item.global_position.z - player.global_position.z).length() < Vector2(gun.global_position.x - player.global_position.x, gun.global_position.z - player.global_position.z).length()):
		var kind: String = item.get_meta("item_kind")
		if hint_label != null:
			hint_label.text = "%s拾取 %s" % [Save.interact_hint(), ITEM_NAMES[kind]]
			hint_label.visible = true
			hint_owned = true
		if Input.is_action_just_pressed("interact"):
			if player.add_item(kind):
				item.remove_from_group("item_pickups")
				item.queue_free()
				Sfx.play("pickup")
			else:
				Game.banner.emit("%s已達上限" % ITEM_NAMES[kind])
		return
	if gun == null:
		if hint_owned and hint_label != null:
			hint_label.visible = false
		hint_owned = false
		return
	var id: String = gun.get_meta("gun_id")
	if hint_label != null:
		hint_label.text = "%s拾取 %s" % [Save.interact_hint(), WeaponDB.WEAPONS[id]["name"]]
		hint_label.visible = true
		hint_owned = true
	if Input.is_action_just_pressed("interact") and weapon != null:
		var ammo: int = gun.get_meta("gun_ammo")
		var reserve: int = gun.get_meta("gun_reserve")
		gun.remove_from_group("gun_pickups")
		gun.queue_free()
		var dropped: Dictionary = weapon.give_gun(id, ammo, reserve)
		Sfx.play("pickup")
		if not dropped.is_empty():
			var fwd := -player.global_transform.basis.z
			spawn_gun(dropped["id"], player.global_position + fwd * 1.8, dropped["ammo"], dropped["reserve"])
		if hint_label != null:
			hint_label.visible = false


func _airdrop_logic(delta: float) -> void:
	if airdrop == null or airdrop_opened:
		return
	if not airdrop.is_landed():
		if hint_label != null:
			hint_owned = false
		return
	airdrop_land_time += delta
	var near: bool = player.global_position.distance_to(airdrop.global_position) < 3.8
	if hint_label != null:
		if near:
			hint_label.text = "%s開啟空投" % Save.interact_hint()
			hint_label.visible = true
			hint_owned = true
		elif hint_owned:
			hint_label.visible = false
			hint_owned = false
	if (near and Input.is_action_just_pressed("interact")) or airdrop_land_time > 40.0:
		if hint_label != null:
			hint_label.visible = false
		airdrop.open()
