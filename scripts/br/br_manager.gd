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
var airdrop_land_time: float = 0.0
var airdrop_opened: bool = false


func _ready() -> void:
	if not Game.is_br():
		set_process(false)
		return
	_start_match.call_deferred()


func _start_match() -> void:
	# 等地圖碰撞體註冊進物理空間
	await get_tree().physics_frame
	await get_tree().physics_frame

	player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	weapon = player.get_node_or_null("Head/Camera3D/Weapon") as Node3D
	hint_label = get_node_or_null("/root/Main/UI/PickupHint") as Label
	player.add_to_group("combatants")
	Game.br_alive = Game.BR_PLAYERS

	# 玩家出生點：外圍，面向地圖中心
	var spawn := ground_point(Vector3.ZERO, 55.0, 85.0)
	player.global_position = spawn
	player.rotation.y = atan2(spawn.x, spawn.z)

	# 近身補給：開局附近有幾把槍
	for i in 3:
		spawn_gun(_random_gun(), ground_point(spawn, 4.0, 12.0))

	_spawn_bots(spawn)
	_spawn_loot()
	_build_zone()
	_begin_hold()
	started = true
	Game.banner.emit("大逃殺開始！撿槍、活到最後")


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
		add_child(bot)
		bot.global_position = pos
		bots.append(bot)
		# 每個 AI 出生點附近放兩把槍
		for j in 2:
			spawn_gun(_random_gun(), ground_point(pos, 3.0, 9.0))


func _spawn_loot() -> void:
	for i in 30:
		spawn_gun(_random_gun(), ground_point(Vector3.ZERO, 0.0, 95.0))
	for i in 22:
		var pk := PICKUP_SCENE.instantiate()
		pk.set("pickup_type", i % 2)
		var gp := ground_point(Vector3.ZERO, 0.0, 95.0)
		pk.position = Vector3(gp.x, 1.0, gp.z)
		add_child(pk)


# ---------- 地上槍枝 ----------

func spawn_gun(id: String, pos: Vector3, ammo: int = -1, reserve: int = -1) -> Node3D:
	var def: Dictionary = WeaponDB.WEAPONS[id]
	var n := Node3D.new()
	n.position = Vector3(pos.x, 0.0, pos.z)
	n.set_meta("gun_id", id)
	n.set_meta("gun_ammo", ammo)
	n.set_meta("gun_reserve", reserve)
	n.add_to_group("gun_pickups")

	var model := Node3D.new()
	model.position = Vector3(0.0, 0.9, 0.0)
	model.scale = Vector3.ONE * 1.8
	n.add_child(model)
	WeaponDB.build_model(model, id, "default")

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
		Game.banner.emit("安全區開始縮小！")


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
	for b in bots:
		var bot := b as Node3D
		if not bool(bot.get("is_dead")) and _outside(bot):
			bot.take_damage(dps, null)


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
	airdrop.landed.connect(func() -> void: Game.banner.emit("空投已著陸！靠近並按 E 開啟"))
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
	for g in get_tree().get_nodes_in_group("gun_pickups"):
		var model := (g as Node3D).get_child(0) as Node3D
		model.rotate_y(delta * 1.4)

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
	if player.is_dead:
		return
	var gun := nearest_gun(player.global_position, 2.8)
	if gun == null:
		if hint_owned and hint_label != null:
			hint_label.visible = false
		hint_owned = false
		return
	var id: String = gun.get_meta("gun_id")
	if hint_label != null:
		hint_label.text = "按 E 拾取 %s" % WeaponDB.WEAPONS[id]["name"]
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
			hint_label.text = "按 E 開啟空投"
			hint_label.visible = true
			hint_owned = true
		elif hint_owned:
			hint_label.visible = false
			hint_owned = false
	if (near and Input.is_action_just_pressed("interact")) or airdrop_land_time > 40.0:
		if hint_label != null:
			hint_label.visible = false
		airdrop.open()
