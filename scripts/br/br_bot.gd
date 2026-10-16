extends CharacterBody3D
# 大逃殺 AI 玩家：撿槍、跑安全區、發現敵人後交戰（會瞄準、掃射、換彈）

const WeaponDB = preload("res://scripts/data/weapon_db.gd")

const SIGHT_RANGE: float = 55.0

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
	health -= damage * (1.0 - armor)
	flash_t = 0.12
	if source != null and source != self:
		last_attacker = source
		if target == null or not is_instance_valid(target):
			target = source as Node3D
			react_timer = maxf(react_timer, 0.35 / skill)
	if health <= 0.0:
		die()


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
	var tw := create_tween()
	tw.tween_property(self, "rotation:x", -PI / 2.0, 0.35)
	tw.tween_interval(6.0)
	tw.tween_callback(queue_free)


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


func _find_target() -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for c in get_tree().get_nodes_in_group("combatants"):
		var n := c as Node3D
		if n == null or n == self or bool(n.get("is_dead")):
			continue
		var d := global_position.distance_to(n.global_position)
		var sight := SIGHT_RANGE * (0.7 if n.get("crouching") == true else 1.0)
		if d > sight or d >= best_d:
			continue
		if _can_see(n):
			best = n
			best_d = d
	return best


func _think() -> void:
	var prev := target
	if target != null and (not is_instance_valid(target) or bool(target.get("is_dead"))):
		target = null
	var seen := _find_target()
	if seen != null:
		if seen != prev:
			react_timer = randf_range(0.35, 0.8) / skill
		target = seen
		target_visible = true
	else:
		target_visible = false
		# 目標跟丟：追擊一小段距離
		if target != null and global_position.distance_to(target.global_position) > SIGHT_RANGE:
			target = null

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
	elif target != null:
		has_goal = false
	elif not has_goal or global_position.distance_to(goal) < 2.5:
		# 已有槍：順手換更好的槍，否則往安全區中心附近移動
		var gun2: Node3D = manager.nearest_gun(global_position, 22.0)
		if gun2 != null and weapon_value(str(gun2.get_meta("gun_id"))) > weapon_value(weapon_id) + 15.0:
			goal = gun2.global_position
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

	if flash_t > 0.0:
		flash_t = maxf(flash_t - delta, 0.0)
		_update_tint()
	elif tint_mats.size() > 0 and (tint_mats[0] as StandardMaterial3D).emission_energy_multiplier > 0.0:
		_update_tint()

	fire_timer = maxf(fire_timer - delta, 0.0)
	react_timer = maxf(react_timer - delta, 0.0)
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
	var combat := target != null and is_instance_valid(target) and target_visible and has_weapon()

	if combat:
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
		_try_shoot(dist)
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
		# 看不見目標但還記得位置：靠近搜索
		var to_s := target.global_position - global_position
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

	var origin := _eye() + (-global_transform.basis.z) * 0.4
	var aim := _chest_of(target)
	var err := deg_to_rad((float(def["spread"]) + 1.2 + dist * 0.07) / skill)
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
