extends CharacterBody3D
# 大逃殺 AI 玩家：撿槍、跑安全區、發現敵人後交戰（會瞄準、掃射、換彈）

const WeaponDB = preload("res://scripts/data/weapon_db.gd")
const GrenadeScript = preload("res://scripts/br/grenade.gd")
const DeathAnim = preload("res://scripts/systems/death_anim.gd")

const SIGHT_RANGE: float = 55.0
const FOV_COS: float = 0.5            # 視野半角 60°（總視野 120°）
const LOSE_SIGHT_TIME: float = 1.5    # 目標離開視野後，最多往最後位置搜索這麼久就放棄

var bot_name: String = "Bot"
var is_dead: bool = false
var max_health: float = 100.0
var health: float = 100.0
var armor: float = 0.0
var skill: float = 1.0          # 0.7 ~ 1.3，影響瞄準與反應

var weapon_id: String = ""
var ammo: int = 0
var reserve: int = 0
var reload_left: float = 0.0
var fire_timer: float = 0.0
var react_timer: float = 0.0

var manager: Node = null
var target: Node3D = null
var target_visible: bool = false
var spot_target: Node3D = null    # 正在「察覺中」的對象（尚未鎖定）
var spot_time: float = 0.0
var spot_need: float = 0.6
var lost_time: float = 0.0
var last_seen_pos: Vector3 = Vector3.ZERO
var vision_timer: float = 0.0
var alert_timer: float = 0.0      # 被打到後轉頭查看的時間
var alert_pos: Vector3 = Vector3.ZERO
var aim_time: float = 0.0         # 鎖定後瞄準穩定度（越久越準）
var scan_t: float = 0.0
var last_attacker: Node = null
var think_timer: float = 0.0
var goal: Vector3 = Vector3.ZERO
var has_goal: bool = false
var move_speed: float = 4.2
var gravity: float = 9.8
var side_dir: float = 1.0
var side_timer: float = 0.0
var strafe_dir: float = 1.0
var strafe_timer: float = 1.0
var flash_t: float = 0.0
var stuck_timer: float = 0.0

# 道具與戰術
var grenades: int = 0
var medkits: int = 0
var plates: int = 0
var shield: float = 0.0
var heal_t: float = 0.0
var heal_kind: String = ""
var grenade_cd: float = 4.0
var flee_t: float = 0.0
var dropping: bool = false
var canopy: Node3D = null

# 外觀
var tint_mats: Array = []
var legs: Array = []
var arms: Array = []
var torso: Node3D
var weapon_holder: Node3D
var name_label: Label3D
var walk_phase: float = 0.0
var shirt_color: Color = Color.GRAY


func _ready() -> void:
	add_to_group("br_bots")
	add_to_group("combatants")
	health = max_health
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	add_child(col)
	think_timer = randf() * 0.3
	vision_timer = randf() * 0.12
	scan_t = randf() * TAU
	_build_visuals()
	_refresh_weapon_model()


# ---------- 外觀 ----------

func _tint_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	m.emission_enabled = true
	m.emission = Color.WHITE
	m.emission_energy_multiplier = 0.0
	tint_mats.append(m)
	return m


func _add_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _build_visuals() -> void:
	var skin := _tint_mat([Color(0.85, 0.68, 0.55), Color(0.7, 0.52, 0.4), Color(0.55, 0.4, 0.3), Color(0.92, 0.78, 0.66)].pick_random())
	var shirt := _tint_mat(shirt_color)
	var pants := _tint_mat(Color(0.15, 0.17, 0.22).lerp(shirt_color, 0.25))
	var vest := _tint_mat(shirt_color.darkened(0.45))
	var dark := _tint_mat(Color(0.07, 0.07, 0.08))
	var helm := _tint_mat(shirt_color.lerp(Color(0.2, 0.22, 0.2), 0.6))

	for sx in [-1.0, 1.0]:
		var leg := _pivot(self, Vector3(sx * 0.11, 0.82, 0.0))
		_add_box(leg, Vector3(0.16, 0.5, 0.18), Vector3(0.0, -0.25, 0.0), pants)
		_add_box(leg, Vector3(0.17, 0.08, 0.27), Vector3(0.0, -0.53, -0.04), dark)
		legs.append(leg)

	torso = _pivot(self, Vector3(0.0, 0.82, 0.0))
	_add_box(torso, Vector3(0.46, 0.6, 0.26), Vector3(0.0, 0.31, 0.0), shirt)
	_add_box(torso, Vector3(0.48, 0.4, 0.3), Vector3(0.0, 0.36, 0.0), vest)
	_add_box(torso, Vector3(0.2, 0.2, 0.1), Vector3(0.0, 0.22, 0.17), dark)   # 背包

	var head := _pivot(torso, Vector3(0.0, 0.66, 0.0))
	var sphere := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.34
	sm.radial_segments = 12
	sm.rings = 6
	sphere.mesh = sm
	sphere.material_override = skin
	sphere.position = Vector3(0.0, 0.14, 0.0)
	sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	head.add_child(sphere)
	_add_box(head, Vector3(0.34, 0.14, 0.34), Vector3(0.0, 0.25, 0.0), helm)       # 頭盔
	_add_box(head, Vector3(0.28, 0.05, 0.05), Vector3(0.0, 0.19, -0.17), dark)       # 護目鏡

	for sx in [-1.0, 1.0]:
		var shoulder := _pivot(torso, Vector3(sx * 0.3, 0.52, 0.0))
		_add_box(shoulder, Vector3(0.13, 0.3, 0.13), Vector3(0.0, -0.15, 0.0), shirt)
		var elbow := _pivot(shoulder, Vector3(0.0, -0.3, 0.0))
		_add_box(elbow, Vector3(0.1, 0.28, 0.1), Vector3(0.0, -0.14, 0.0), skin)
		arms.append(shoulder)
		elbow.rotation.x = 0.25

	weapon_holder = _pivot(torso, Vector3(0.14, 0.4, -0.3))

	name_label = Label3D.new()
	name_label.text = bot_name
	name_label.font_size = 40
	name_label.pixel_size = 0.0055
	name_label.outline_size = 10
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.no_depth_test = true
	name_label.position = Vector3(0.0, 2.15, 0.0)
	name_label.visibility_range_end = 38.0
	add_child(name_label)


func _refresh_weapon_model() -> void:
	if weapon_holder == null:
		return
	for c in weapon_holder.get_children():
		c.queue_free()
	if weapon_id != "":
		WeaponDB.build_model(weapon_holder, weapon_id, "default")


func has_weapon() -> bool:
	return weapon_id != ""


func give_weapon(id: String, new_ammo: int, new_reserve: int) -> void:
	weapon_id = id
	ammo = new_ammo
	reserve = new_reserve
	reload_left = 0.0
	_refresh_weapon_model()


func weapon_value(id: String) -> float:
	var def: Dictionary = WeaponDB.WEAPONS[id]
	return float(def["damage"]) * float(def["pellets"]) / float(def["fire_rate"]) * 0.25 + float(def["range"]) * 0.5


# ---------- 受傷與死亡 ----------

func take_damage(damage: float, source: Node = null) -> void:
	if is_dead:
		return
	if dropping and source != null:
		return   # 跳傘中不受玩家 / AI 攻擊；環境傷害（source 為空）仍有效，避免卡住的 AI 無敵
	var remaining := damage * (1.0 - armor)
	if shield > 0.0:
		var absorbed := minf(shield, remaining)
		shield -= absorbed
		remaining -= absorbed
	health -= remaining
	flash_t = 0.12
	if heal_t > 0.0:
		heal_t = 0.0   # 受傷打斷治療
	if source != null and source != self:
		last_attacker = source
		# 被打到：只會轉頭往來源方向查看，需要在視野中看到對方才會交戰
		var src := source as Node3D
		if src != null and (target == null or not is_instance_valid(target)):
			alert_timer = 3.0
			alert_pos = src.global_position
	if health <= 0.0:
		die()


# ---------- 道具 / 跳傘 / 聽覺 ----------

func give_item(kind: String) -> void:
	match kind:
		"grenade":
			grenades = mini(grenades + 1, 4)
		"medkit":
			medkits = mini(medkits + 1, 4)
		"plate":
			plates = mini(plates + 1, 4)


func wants_item(kind: String) -> bool:
	match kind:
		"grenade":
			return grenades < 3
		"medkit":
			return medkits < 2
		"plate":
			return plates < 2
	return false


# 聽到槍聲 / 爆炸：轉頭查看，有一定機率前往聲音來源（不會直接鎖定目標）
func hear(pos: Vector3, source: Node) -> void:
	if is_dead or dropping or heal_t > 0.0 or source == self or target != null:
		return
	alert_timer = maxf(alert_timer, 2.5)
	alert_pos = pos
	if has_weapon() and randf() < 0.45:
		goal = pos + Vector3(randf_range(-4.0, 4.0), 0.0, randf_range(-4.0, 4.0))
		has_goal = true


func start_drop(height: float) -> void:
	dropping = true
	global_position.y = height
	canopy = Node3D.new()
	add_child(canopy)
	var dome := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 1.6
	sph.height = 1.6
	sph.is_hemisphere = true
	dome.mesh = sph
	var m := StandardMaterial3D.new()
	m.albedo_color = shirt_color.lightened(0.2)
	dome.material_override = m
	dome.position = Vector3(0, 3.0, 0)
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	canopy.add_child(dome)
	for i in 4:
		var a := float(i) * TAU / 4.0
		var line := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.02, 2.4, 0.02)
		line.mesh = bm
		line.position = Vector3(cos(a) * 0.7, 1.7, sin(a) * 0.7)
		line.rotation = Vector3(-sin(a) * 0.4, 0.0, cos(a) * 0.4)
		canopy.add_child(line)


# 保底：強制結束跳傘並放到指定地面位置（跳傘卡住時由管理器呼叫）
func force_land(pos: Vector3) -> void:
	dropping = false
	if canopy != null:
		canopy.queue_free()
		canopy = null
	velocity = Vector3.ZERO
	global_position = pos


func _drop_physics(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	velocity.y = -12.0 if global_position.y > 50.0 else -5.5
	move_and_slide()
	if is_on_floor():
		dropping = false
		if canopy != null:
			canopy.queue_free()
			canopy = null
		velocity = Vector3.ZERO
	_animate(delta)


func _finish_heal() -> void:
	if heal_kind == "medkit" and medkits > 0:
		medkits -= 1
		health = minf(health + max_health * 0.6, max_health)
	elif heal_kind == "plate" and plates > 0:
		plates -= 1
		shield = minf(shield + 25.0, 50.0)
	heal_kind = ""


# 戰術：殘血且被盯上 → 找掩體撤退；沒被盯上 → 用醫療包 / 護甲板
func _tactics() -> void:
	var hp_frac := health / max_health
	var threatened := target != null and is_instance_valid(target) and target_visible
	if hp_frac < 0.4 and threatened and flee_t <= 0.0 and (medkits > 0 or randf() < 0.5):
		var cover := _find_cover((target as Node3D).global_position)
		if cover != Vector3.INF:
			goal = cover
			has_goal = true
			flee_t = 3.5
	elif not threatened and heal_t <= 0.0 and flee_t <= 0.0:
		if medkits > 0 and hp_frac < 0.7:
			heal_kind = "medkit"
			heal_t = 3.0
		elif plates > 0 and shield < 25.0:
			heal_kind = "plate"
			heal_t = 1.5


# 取樣周圍點：威脅者到該點的視線被擋住就是掩體
func _find_cover(threat_pos: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var best := Vector3.INF
	var best_d := INF
	for i in 12:
		var a := randf() * TAU
		var r := randf_range(4.0, 11.0)
		var p := global_position + Vector3(cos(a) * r, 0.0, sin(a) * r)
		var gq := PhysicsRayQueryParameters3D.create(Vector3(p.x, 30.0, p.z), Vector3(p.x, -1.0, p.z))
		var gh := space.intersect_ray(gq)
		if gh.is_empty() or gh["position"].y > 0.6:
			continue
		p.y = gh["position"].y
		var lq := PhysicsRayQueryParameters3D.create(threat_pos + Vector3(0, 1.4, 0), p + Vector3(0, 1.2, 0))
		if target is CollisionObject3D:
			lq.exclude = [(target as CollisionObject3D).get_rid()]
		if space.intersect_ray(lq).is_empty():
			continue   # 看得到 → 不是掩體
		var d := global_position.distance_to(p)
		if d < best_d:
			best_d = d
			best = p
	return best


func _try_grenade(dist: float) -> void:
	if grenades <= 0 or grenade_cd > 0.0 or react_timer > 0.0 or dist < 8.0 or dist > 30.0 or target == null:
		return
	if randf() > 0.03:
		return
	grenades -= 1
	grenade_cd = 8.0
	var g := Node3D.new()
	g.set_script(GrenadeScript)
	get_tree().current_scene.add_child(g)
	g.global_position = _eye() + Vector3(0, 0.1, 0)
	var flat := (target as Node3D).global_position - global_position
	flat.y = 0.0
	var theta := deg_to_rad(40.0)
	var v := sqrt(flat.length() * 14.0 / sin(2.0 * theta)) * 1.05
	g.launch(flat.normalized() * v * cos(theta) + Vector3.UP * v * sin(theta), self)
	Sfx.play("grenade_pin", -4.0, 0.8)


func die() -> void:
	if is_dead:
		return
	is_dead = true
	remove_from_group("br_bots")
	remove_from_group("combatants")
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	if name_label:
		name_label.visible = false
	if manager != null:
		manager.bot_died(self, last_attacker)
	Sfx.play("die", -6.0, randf_range(0.8, 1.0))
	var away := Vector3.ZERO
	if last_attacker is Node3D:
		away = global_position - (last_attacker as Node3D).global_position
	var parts: Array = []
	parts.append_array(legs)
	parts.append_array(arms)
	DeathAnim.play(self, away, parts, false, 6.0)


# ---------- AI ----------

func _eye() -> Vector3:
	return global_position + Vector3(0.0, 1.55, 0.0)


func _chest_of(n: Node3D) -> Vector3:
	var crouch := false
	if n.has_method("take_damage") and n.get("crouching") == true:
		crouch = true
	return n.global_position + Vector3(0.0, 0.7 if crouch else 1.1, 0.0)


func _can_see(n: Node3D) -> bool:
	var q := PhysicsRayQueryParameters3D.create(_eye(), _chest_of(n))
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and hit["collider"] == n


func _view_forward() -> Vector3:
	var f := -global_transform.basis.z
	f.y = 0.0
	f = f.normalized()
	if target == null:
		# 巡視時視線左右掃動
		f = f.rotated(Vector3.UP, sin(scan_t) * 0.6)
	return f


# 目標是否進入視野：距離、視野角、無遮蔽
func _perceives(n: Node3D) -> bool:
	var to := n.global_position - global_position
	to.y = 0.0
	var d := to.length()
	var sight := SIGHT_RANGE * (0.7 if n.get("crouching") == true else 1.0)
	if d > sight:
		return false
	if d > 1.5 and _view_forward().dot(to / d) < FOV_COS:
		return false
	return _can_see(n)


func _find_target() -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for c in get_tree().get_nodes_in_group("combatants"):
		var n := c as Node3D
		if n == null or n == self or bool(n.get("is_dead")):
			continue
		var d := global_position.distance_to(n.global_position)
		if d >= best_d or d > SIGHT_RANGE:
			continue
		if _perceives(n):
			best = n
			best_d = d
	return best


func _update_vision(dt: float) -> void:
	if target != null and (not is_instance_valid(target) or bool(target.get("is_dead"))):
		_drop_target()
	if target != null:
		if _perceives(target):
			target_visible = true
			lost_time = 0.0
			last_seen_pos = target.global_position
		else:
			target_visible = false
			lost_time += dt
			if lost_time > LOSE_SIGHT_TIME:
				_drop_target()   # 離開視野一段時間 → 放棄追蹤
		return
	var cand := _find_target()
	if cand == null:
		spot_target = null
		spot_time = 0.0
		return
	if cand != spot_target:
		spot_target = cand
		spot_time = 0.0
		var dist := global_position.distance_to(cand.global_position)
		spot_need = randf_range(0.45, 0.9) * (1.0 + dist / SIGHT_RANGE)
		if cand.get("crouching") == true:
			spot_need *= 1.4
		if alert_timer > 0.0:
			spot_need *= 0.5   # 剛被攻擊，警覺性較高
		spot_need /= skill
	spot_time += dt
	if spot_time >= spot_need:
		# 反應完成：鎖定目標，再加上舉槍瞄準的延遲才會開火
		target = cand
		target_visible = true
		lost_time = 0.0
		last_seen_pos = cand.global_position
		react_timer = randf_range(0.3, 0.6) / skill
		aim_time = 0.0
		spot_target = null
		spot_time = 0.0


func _drop_target() -> void:
	target = null
	target_visible = false
	lost_time = 0.0
	aim_time = 0.0
	has_goal = false


func _think() -> void:
	_tactics()
	var zone_c: Vector3 = manager.zone_center
	var zone_r: float = manager.zone_radius
	var dz := Vector2(global_position.x - zone_c.x, global_position.z - zone_c.z).length()
	var outside := dz > zone_r - 4.0

	if outside:
		goal = zone_c + Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * minf(zone_r * 0.4, 12.0)
		has_goal = true
	elif not has_weapon() or (ammo + reserve) <= 0:
		var gun: Node3D = manager.nearest_gun(global_position, 90.0)
		if gun != null:
			goal = gun.global_position
			has_goal = true
		elif not has_goal or global_position.distance_to(goal) < 2.0:
			_pick_roam_goal(zone_c, zone_r)
	elif target != null and flee_t <= 0.0:
		has_goal = false
	elif not has_goal or global_position.distance_to(goal) < 2.5:
		# 已有槍：順手換更好的槍，否則往安全區中心附近移動
		var gun2: Node3D = manager.nearest_gun(global_position, 22.0)
		if gun2 != null and weapon_value(str(gun2.get_meta("gun_id"))) > weapon_value(weapon_id) + 15.0:
			goal = gun2.global_position
			has_goal = true
		else:
			var it: Node3D = manager.nearest_item(global_position, 24.0)
			var sup: Node3D = manager.nearest_supply(global_position, 70.0)
			if it != null and wants_item(str(it.get_meta("item_kind"))):
				goal = it.global_position
				has_goal = true
			elif sup != null and randf() < 0.6:
				goal = sup.global_position
				has_goal = true
			else:
				_pick_roam_goal(zone_c, zone_r)


func _pick_roam_goal(zone_c: Vector3, zone_r: float) -> void:
	var a := randf() * TAU
	var r := randf_range(0.0, maxf(zone_r * 0.65, 3.0))
	goal = zone_c + Vector3(cos(a) * r, 0.0, sin(a) * r)
	has_goal = true


func _physics_process(delta: float) -> void:
	if is_dead or manager == null:
		return
	if not Game.is_playing():
		return
	if dropping:
		_drop_physics(delta)
		return
	grenade_cd = maxf(grenade_cd - delta, 0.0)
	flee_t = maxf(flee_t - delta, 0.0)

	if flash_t > 0.0:
		flash_t = maxf(flash_t - delta, 0.0)
		_update_tint()
	elif tint_mats.size() > 0 and (tint_mats[0] as StandardMaterial3D).emission_energy_multiplier > 0.0:
		_update_tint()

	fire_timer = maxf(fire_timer - delta, 0.0)
	react_timer = maxf(react_timer - delta, 0.0)
	alert_timer = maxf(alert_timer - delta, 0.0)
	scan_t += delta * 1.1
	vision_timer -= delta
	if vision_timer <= 0.0:
		vision_timer = 0.12
		_update_vision(0.12)
	if reload_left > 0.0:
		reload_left -= delta
		if reload_left <= 0.0:
			var def: Dictionary = WeaponDB.WEAPONS[weapon_id]
			var load_n := mini(int(def["mag"]) - ammo, reserve)
			ammo += load_n
			reserve -= load_n

	think_timer -= delta
	if think_timer <= 0.0:
		think_timer = 0.3
		_think()

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	var move_dir := Vector3.ZERO
	var speed := move_speed
	var channeling := heal_t > 0.0
	if channeling:
		heal_t -= delta
		if heal_t <= 0.0:
			_finish_heal()
	var combat := target != null and is_instance_valid(target) and target_visible and has_weapon() and not channeling and flee_t <= 0.0
	if flee_t > 0.0:
		speed *= 1.3

	if channeling:
		pass   # 原地使用道具
	elif combat:
		var to_t := target.global_position - global_position
		to_t.y = 0.0
		var dist := to_t.length()
		var def2: Dictionary = WeaponDB.WEAPONS[weapon_id]
		var preferred := clampf(float(def2["range"]) * 0.3, 7.0, 26.0)
		var fwd := to_t.normalized()
		_face(fwd, delta, 10.0)
		strafe_timer -= delta
		if strafe_timer <= 0.0:
			strafe_timer = randf_range(0.8, 2.2)
			strafe_dir = 1.0 if randf() < 0.5 else -1.0
		var side := fwd.cross(Vector3.UP) * strafe_dir
		if dist > preferred + 4.0:
			move_dir = fwd + side * 0.3
		elif dist < preferred - 4.0 and weapon_id != "shotgun":
			move_dir = -fwd * 0.8 + side * 0.5
		else:
			move_dir = side * 0.6
		speed *= 0.85
		aim_time += delta
		_try_shoot(dist)
		_try_grenade(dist)
	elif spot_target != null and is_instance_valid(spot_target):
		# 察覺中：停下腳步轉向可疑對象，還沒決定要不要交戰
		var to_sp := spot_target.global_position - global_position
		to_sp.y = 0.0
		_face(to_sp.normalized(), delta, 7.0)
		speed *= 0.3
		move_dir = Vector3.ZERO
	elif alert_timer > 2.0 and target == null:
		# 被打到：愣一下、轉向來源
		var to_al := alert_pos - global_position
		to_al.y = 0.0
		_face(to_al.normalized(), delta, 9.0)
	elif has_goal:
		var to_g := goal - global_position
		to_g.y = 0.0
		if to_g.length() > 1.2:
			move_dir = to_g.normalized()
			_face(move_dir, delta, 8.0)
		else:
			has_goal = false
			if manager != null:
				manager.bot_try_pickup(self)
	elif target != null and is_instance_valid(target):
		# 目標剛離開視野：只往「最後看到的位置」查看，不會即時追蹤
		var to_s := last_seen_pos - global_position
		to_s.y = 0.0
		if to_s.length() > 3.0:
			move_dir = to_s.normalized()
			_face(move_dir, delta, 8.0)

	# 撿槍
	if has_goal and manager != null and global_position.distance_to(goal) < 2.0:
		manager.bot_try_pickup(self)

	if move_dir != Vector3.ZERO:
		move_dir = move_dir.normalized()
		if side_timer > 0.0:
			side_timer -= delta
			move_dir = move_dir.rotated(Vector3.UP, side_dir * PI / 2.2)
		velocity.x = move_dir.x * speed
		velocity.z = move_dir.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

	move_and_slide()

	# 卡牆就繞行；長時間卡住換目標
	if is_on_wall() and side_timer <= 0.0:
		side_timer = 0.8
		side_dir = 1.0 if randf() < 0.5 else -1.0
		stuck_timer += 0.8
		if stuck_timer > 3.0:
			stuck_timer = 0.0
			has_goal = false
	elif not is_on_wall():
		stuck_timer = maxf(stuck_timer - delta, 0.0)

	_animate(delta)


func _face(dir: Vector3, delta: float, rate: float) -> void:
	if dir.length() < 0.01:
		return
	var target_yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, minf(delta * rate, 1.0))


func _try_shoot(dist: float) -> void:
	if reload_left > 0.0 or fire_timer > 0.0 or react_timer > 0.0:
		return
	var def: Dictionary = WeaponDB.WEAPONS[weapon_id]
	if dist > float(def["range"]):
		return
	if ammo <= 0:
		if reserve > 0:
			reload_left = float(def["reload"]) * 1.2
		else:
			weapon_id = ""
			_refresh_weapon_model()
		return
	ammo -= 1
	fire_timer = float(def["fire_rate"]) * (1.7 if bool(def["auto"]) else 1.4) / skill
	if not bool(def["auto"]):
		fire_timer = maxf(fire_timer, 0.55)

	if manager != null:
		manager.noise(global_position, 48.0, self)
	var origin := _eye() + (-global_transform.basis.z) * 0.4
	var aim := _chest_of(target)
	var warm := 1.0 + maxf(1.0 - aim_time, 0.0) * 2.5   # 剛鎖定時瞄不準，逐漸穩定
	var err := deg_to_rad((float(def["spread"]) + 1.2 + dist * 0.07) * warm / skill)
	var space := get_world_3d().direct_space_state
	var last_end := origin
	for i in int(def["pellets"]):
		var dir := (aim - origin).normalized()
		var side := dir.cross(Vector3.UP).normalized()
		var up := side.cross(dir).normalized()
		dir = (dir + side * randf_range(-err, err) + up * randf_range(-err, err)).normalized()
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * float(def["range"]))
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		var end := origin + dir * float(def["range"])
		if not hit.is_empty():
			end = hit["position"]
			var collider: Object = hit["collider"]
			if collider.has_method("take_damage") and (collider as Node).is_in_group("combatants"):
				var d := origin.distance_to(end)
				var half := float(def["range"]) * 0.5
				var fall := 1.0 if d <= half else lerpf(1.0, 0.35, (d - half) / half)
				collider.take_damage(float(def["damage"]) * 0.75 * fall, self)
		last_end = end
		if i == 0:
			_tracer(origin, end)
	_gunshot()


func _tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 1.0:
		return
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.03, 0.03, length)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.4, 0.9)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(mi)
	mi.global_position = (from + to) * 0.5
	mi.look_at(to, Vector3.UP)
	var tw := mi.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.08)
	tw.tween_callback(mi.queue_free)


func _gunshot() -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = Sfx.sounds["shoot"]
	p.unit_size = 10.0
	p.max_distance = 100.0
	p.volume_db = -3.0
	p.pitch_scale = randf_range(0.9, 1.1)
	get_tree().current_scene.add_child(p)
	p.global_position = global_position + Vector3(0.0, 1.4, 0.0)
	p.finished.connect(p.queue_free)
	p.play()


func _update_tint() -> void:
	var e := flash_t / 0.12 * 2.0
	for m in tint_mats:
		(m as StandardMaterial3D).emission_energy_multiplier = e


func _animate(delta: float) -> void:
	var spd := Vector2(velocity.x, velocity.z).length()
	var k := clampf(spd / 2.5, 0.0, 1.0)
	walk_phase += spd * delta * 2.3
	for i in legs.size():
		(legs[i] as Node3D).rotation.x = sin(walk_phase + float(i) * PI) * 0.7 * k
	var armed := has_weapon()
	for i in arms.size():
		var a := arms[i] as Node3D
		if armed:
			a.rotation.x = lerpf(a.rotation.x, 1.35, minf(delta * 10.0, 1.0))
		else:
			a.rotation.x = lerpf(a.rotation.x, sin(walk_phase + float(i) * PI) * 0.6 * k, minf(delta * 10.0, 1.0))
	torso.position.y = 0.82 + absf(sin(walk_phase)) * 0.035 * k
	if weapon_holder != null:
		weapon_holder.visible = armed
