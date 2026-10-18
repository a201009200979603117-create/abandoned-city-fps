extends Node3D
# 武器：殭屍模式依 Save.selected_weapon 載入；大逃殺模式為雙槍欄位，槍枝需在場上撿取。
# 皮膚取自 Save.selected_skin，裝備加成取自 Save.equipped。

const WeaponDB = preload("res://scripts/data/weapon_db.gd")
const Hitzone = preload("res://scripts/systems/hitzone.gd")
const CombatFX = preload("res://scripts/systems/combat_fx.gd")

var weapon_id: String = ""
var weapon_name: String = ""
var damage: float = 25.0
var fire_rate: float = 0.14
var range_distance: float = 100.0
var magazine_size: int = 30
var reserve_ammo: int = 90
var reload_time: float = 1.3
var recoil_kick: float = 0.012
var pellets: int = 1
var spread_deg: float = 0.0
var automatic: bool = true
var zoom_fov: float = 0.0
var scope_lv: int = 0       # 配件：瞄準鏡等級
var fx: Node3D = null

# 技能加成
var fire_mult: float = 1.0
var damage_mult: float = 1.0
var infinite_ammo: bool = false

# 裝備加成
var equip: Dictionary = {}
var equip_dmg: float = 1.0

var armed: bool = false
var slots: Array = [{}, {}]
var active: int = 0

var current_ammo: int = 30
var fire_timer: float = 0.0
var reload_left: float = 0.0
var kick: float = 0.0
var flash_time: float = 0.0
var trigger_was_down: bool = false
var touch_fire: bool = false
var touch_zoom: bool = false

var camera: Camera3D
var head: Node3D
var player: CharacterBody3D
var base_position: Vector3
var flash_light: OmniLight3D
var spark_material: StandardMaterial3D
var model_root: Node3D
var flash_z: float = -0.55

# 手感狀態
const ADS_POS: Vector3 = Vector3(0.0, -0.165, -0.45)
var ads: float = 0.0
var bloom: float = 0.0            # 連射累積的散佈（度）
var burst_shots: int = 0          # 連續射擊發數，越多後座越大
var since_shot: float = 1.0
var recoil_debt: float = 0.0      # 尚未回正的垂直後座力
var sprint_pose: float = 0.0
var sway: Vector2 = Vector2.ZERO
var last_yaw: float = 0.0
var last_pitch: float = 0.0
var flash_quad: MeshInstance3D
var tracer_material: StandardMaterial3D
var hole_texture: GradientTexture2D
var holes: Array = []
var crosshair: Control
var tracer_pool: Array = []       # [MeshInstance3D, 剩餘時間]
var tracer_idx: int = 0
var spark_pool: Array = []
var spark_idx: int = 0
var hole_pool: Array = []
var hole_idx: int = 0
var shared_box: BoxMesh
var hole_mesh: QuadMesh
var hole_mat: StandardMaterial3D
var spark_mesh: SphereMesh
const TRACER_POOL: int = 8
const SPARK_POOL: int = 6
const HOLE_POOL: int = 40

@onready var ammo_label: Label = get_node_or_null("/root/Main/UI/AmmoLabel")
@onready var weapon_label: Label = get_node_or_null("/root/Main/UI/WeaponLabel")


func _ready() -> void:
	camera = get_parent() as Camera3D
	head = camera.get_parent() as Node3D
	player = head.get_parent() as CharacterBody3D
	base_position = position

	equip = Save.equip_totals()
	equip_dmg = 1.0 + float(equip["dmg"]) / 100.0

	spark_material = StandardMaterial3D.new()
	spark_material.albedo_color = Color(1.0, 0.7, 0.25)
	spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	tracer_material = StandardMaterial3D.new()
	tracer_material.albedo_color = Color(1.0, 0.85, 0.5, 0.8)
	tracer_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tracer_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hole_texture = GradientTexture2D.new()
	hole_texture.fill = GradientTexture2D.FILL_RADIAL
	hole_texture.fill_from = Vector2(0.5, 0.5)
	hole_texture.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0, 0, 0, 0.9), Color(0.02, 0.02, 0.02, 0.85), Color(0, 0, 0, 0)])
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	hole_texture.gradient = g
	hole_texture.width = 32
	hole_texture.height = 32

	_make_effect_pools()
	fx = CombatFX.new()
	var fx_host: Node = get_node_or_null("/root/Main")
	(fx_host if fx_host != null else self).add_child.call_deferred(fx)

	flash_light = OmniLight3D.new()
	flash_light.light_color = Color(1.0, 0.8, 0.4)
	flash_light.light_energy = 3.0
	flash_light.omni_range = 6.0
	flash_light.visible = false
	add_child(flash_light)

	flash_quad = MeshInstance3D.new()
	var fq := QuadMesh.new()
	fq.size = Vector2(0.22, 0.22)
	flash_quad.mesh = fq
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.albedo_color = Color(1.0, 0.7, 0.3)
	fm.albedo_texture = hole_texture
	flash_quad.material_override = fm
	flash_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash_quad.visible = false
	add_child(flash_quad)
	crosshair = get_node_or_null("/root/Main/UI/Crosshair") as Control
	last_yaw = player.rotation.y
	last_pitch = head.rotation.x

	if Game.is_br():
		slots = [{}, {}]   # 大逃殺：徒手開局，槍要自己撿
	else:
		slots = [_new_slot(Save.selected_weapon), {}]
	active = 0
	_apply_slot()


func _new_slot(id: String, ammo: int = -1, reserve: int = -1) -> Dictionary:
	var def: Dictionary = WeaponDB.WEAPONS[id]
	return {
		"id": id,
		"ammo": _mag_for(id) if ammo < 0 else ammo,
		"reserve": int(float(def["reserve"]) * (1.0 + float(equip["ammo"]) / 100.0)) if reserve < 0 else reserve,
	}


# 擴容彈匣配件後的彈匣容量
func _mag_for(id: String) -> int:
	var def: Dictionary = WeaponDB.WEAPONS[id]
	return int(ceil(float(def["mag"]) * (1.0 + 0.2 * float(Save.attach_level(id, "mag")))))


func _store_slot() -> void:
	if armed:
		slots[active] = {"id": weapon_id, "ammo": current_ammo, "reserve": reserve_ammo}


# 依目前欄位載入數值與模型
func _apply_slot() -> void:
	if model_root != null:
		model_root.queue_free()
		model_root = null
	reload_left = 0.0
	flash_light.visible = false
	var slot: Dictionary = slots[active]
	if slot.is_empty():
		armed = false
		weapon_id = ""
		weapon_name = "徒手"
		current_ammo = 0
		reserve_ammo = 0
		zoom_fov = 0.0
		update_ammo_ui()
		return
	armed = true
	weapon_id = slot["id"]
	var def: Dictionary = WeaponDB.WEAPONS[weapon_id]
	weapon_name = def["name"]
	damage = def["damage"]
	fire_rate = def["fire_rate"]
	range_distance = def["range"]
	magazine_size = _mag_for(weapon_id)
	reload_time = maxf(float(def["reload"]) * (1.0 - float(equip["reload"]) / 100.0), 0.4)
	# 配件加成
	recoil_kick = float(def["recoil"]) * (1.0 - 0.1 * float(Save.attach_level(weapon_id, "grip")))
	pellets = def["pellets"]
	spread_deg = float(def["spread"]) * (1.0 - 0.1 * float(Save.attach_level(weapon_id, "muzzle")))
	automatic = def["auto"]
	scope_lv = Save.attach_level(weapon_id, "scope")
	zoom_fov = float(def["zoom"]) * (1.0 - 0.06 * float(scope_lv)) if float(def["zoom"]) > 0.0 else 0.0
	current_ammo = slot["ammo"]
	reserve_ammo = slot["reserve"]
	model_root = Node3D.new()
	add_child(model_root)
	flash_z = WeaponDB.build_model(model_root, weapon_id, Save.selected_skin)
	flash_light.position = Vector3(0.0, 0.02, flash_z)
	flash_quad.position = Vector3(0.0, 0.02, flash_z)
	flash_quad.visible = false
	fire_timer = 0.25
	update_ammo_ui()


func switch_to(i: int) -> void:
	if i == active or i < 0 or i >= slots.size():
		return
	_store_slot()
	active = i
	_apply_slot()


# 撿槍：有空欄位放空欄位，否則換掉手上這把。回傳被換下來的槍（供掉落），沒有則為空字典
func give_gun(id: String, ammo: int = -1, reserve: int = -1) -> Dictionary:
	_store_slot()
	var target := -1
	for i in slots.size():
		if (slots[i] as Dictionary).is_empty():
			target = i
			break
	var dropped: Dictionary = {}
	if target == -1:
		target = active
		dropped = slots[active]
	slots[target] = _new_slot(id, ammo, reserve)
	active = target
	_apply_slot()
	return dropped


func add_reserve(amount: int) -> void:
	if armed:
		reserve_ammo += amount
		update_ammo_ui()
	else:
		# 徒手時把備彈補給第一把有槍的欄位
		for i in slots.size():
			var s: Dictionary = slots[i]
			if not s.is_empty():
				s["reserve"] = int(s["reserve"]) + amount
				break


func _unhandled_input(event: InputEvent) -> void:
	if not Game.is_br() or not Game.is_playing() or player.is_dead:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1:
				switch_to(0)
			KEY_2:
				switch_to(1)
			KEY_Q:
				switch_to(1 - active)


func _process(delta: float) -> void:
	# 後座力恢復與槍口閃光
	kick = move_toward(kick, 0.0, delta * 9.0)
	if flash_time > 0.0:
		flash_time -= delta
		if flash_time <= 0.0:
			flash_light.visible = false
			flash_quad.visible = false
	_update_pose(delta)
	_update_recoil_recovery(delta)
	_update_tracers(delta)

	fire_timer = maxf(fire_timer - delta, 0.0)

	if reload_left > 0.0:
		reload_left -= delta
		if reload_left <= 0.0:
			_finish_reload()

	if player.is_dead or not Game.is_playing() or bool(player.get("skydiving")):
		return

	_update_zoom(delta)

	if not armed:
		return

	if Input.is_action_just_pressed("reload"):
		start_reload()

	var down := false
	if Save.touch_mode:
		down = touch_fire
	else:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return
		down = Input.is_key_pressed(KEY_F) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var want_fire := down if automatic else (down and not trigger_was_down)
	trigger_was_down = down
	if want_fire and fire_timer <= 0.0 and reload_left <= 0.0:   # 奔跑中也可射擊
		shoot()


func _ads_held() -> bool:
	if Save.touch_mode:
		return touch_zoom
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func _update_zoom(delta: float) -> void:
	# 奔跑中按開鏡：自動停止奔跑、切成走路並開鏡（玩家端以 ads_wanted 取消奔跑）
	var want := armed and reload_left <= 0.0 and _ads_held()
	player.set("ads_wanted", want)
	ads = move_toward(ads, 1.0 if want else 0.0, delta * (6.0 if zoom_fov > 0.0 else 8.0) * (1.0 + 0.1 * float(scope_lv)))
	player.set("ads_factor", ads)
	var ads_fov := zoom_fov if zoom_fov > 0.0 else Save.fov * (0.82 - 0.04 * float(scope_lv))
	camera.fov = lerpf(Save.fov, ads_fov, smoothstep(0.0, 1.0, ads))
	if crosshair != null:
		crosshair.modulate.a = 1.0 - ads * (0.9 if zoom_fov > 0.0 else 0.5)


# 持槍姿勢：瞄準、衝刺、換彈、走路晃動、視角延遲與後座力
func _update_pose(delta: float) -> void:
	var yaw: float = player.rotation.y
	var pitch: float = head.rotation.x
	var d_yaw := wrapf(yaw - last_yaw, -PI, PI)
	var d_pitch := pitch - last_pitch
	last_yaw = yaw
	last_pitch = pitch
	sway = sway.lerp(Vector2(clampf(-d_yaw * 1.6, -0.06, 0.06), clampf(-d_pitch * 1.6, -0.05, 0.05)), minf(delta * 10.0, 1.0))

	var moving := Vector2(player.velocity.x, player.velocity.z).length()
	var sprint_target := 1.0 if (armed and bool(player.get("is_sprinting")) and moving > 1.0 and not trigger_was_down) else 0.0   # 扣著扳機時舉槍（奔跑中也能射擊）
	sprint_pose = move_toward(sprint_pose, sprint_target, delta * 6.0)

	var bob_t: float = float(player.get("bob_time"))
	var walk := clampf(moving / 5.0, 0.0, 1.0) * (1.0 - ads * 0.85) * (1.0 if player.is_on_floor() else 0.0)
	var bob := Vector3(cos(bob_t * 0.5) * 0.012, sin(bob_t) * 0.008, 0.0) * walk

	var pos := base_position.lerp(ADS_POS, smoothstep(0.0, 1.0, ads))
	pos += bob + Vector3(sway.x, sway.y, 0.0) * 0.5 * (1.0 - ads * 0.7)
	pos += Vector3(0.0, 0.012, 0.07) * kick * (1.0 - ads * 0.4)
	pos += Vector3(0.05, -0.07, 0.03) * sprint_pose
	position = pos

	var rot := Vector3(sway.y * 0.8 + kick * 0.04, sway.x * 0.8, -sway.x * 0.5)
	rot += Vector3(-0.18, 0.7, 0.12) * sprint_pose
	rotation = rot

	# 換彈：槍身下沉、傾斜再回位
	if model_root != null:
		var r := 0.0
		if reload_left > 0.0 and reload_time > 0.0:
			r = sin(PI * clampf(1.0 - reload_left / reload_time, 0.0, 1.0))
		model_root.position = Vector3(0.0, -0.12, 0.05) * r
		model_root.rotation = Vector3(0.55 * r, 0.0, -0.35 * r)


func _update_recoil_recovery(delta: float) -> void:
	since_shot += delta
	if since_shot > 0.1:
		bloom = move_toward(bloom, 0.0, delta * 1.2)
	if since_shot > 0.12:
		if since_shot > 0.35:
			burst_shots = 0
		var step := minf(recoil_debt, delta * (0.5 + recoil_debt * 6.0))
		head.rotation.x -= step
		recoil_debt -= step


func _current_spread() -> float:
	var s := spread_deg
	if zoom_fov > 0.0:
		s += 2.5 * (1.0 - ads)   # 狙擊槍腰射很不準
	s *= lerpf(1.0, 0.35 * (1.0 - 0.1 * float(scope_lv)), ads)
	s += bloom
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	s += clampf(speed / 5.0, 0.0, 1.4) * (0.5 if ads > 0.5 else 1.3)
	if not player.is_on_floor():
		s += 3.0
	if bool(player.get("crouching")):
		s *= 0.6
	return s


func shoot() -> void:
	fire_timer = fire_rate * fire_mult

	if current_ammo <= 0:
		Sfx.play("empty")
		fire_timer = 0.3
		start_reload()
		return

	if not infinite_ammo:
		current_ammo -= 1
	update_ammo_ui()

	kick = 1.0
	# 後座力：連射越久越大，瞄準時減半；水平方向隨機偏移
	burst_shots += 1
	since_shot = 0.0
	var climb := recoil_kick * (1.0 + minf(float(burst_shots), 10.0) * 0.07) * lerpf(1.0, 0.55, ads)
	if bool(player.get("crouching")):
		climb *= 0.8
	head.rotation.x = minf(head.rotation.x + climb, deg_to_rad(85.0))
	recoil_debt += climb * 0.6
	player.rotate_y(randf_range(-0.45, 0.45) * climb)
	bloom = minf(bloom + 0.18 + recoil_kick * 6.0, 2.5)
	if player.has_method("add_shake"):
		player.add_shake(0.12 + recoil_kick * 3.0)
	flash_light.visible = true
	flash_quad.visible = true
	flash_quad.rotation.z = randf() * TAU
	flash_quad.scale = Vector3.ONE * randf_range(0.8, 1.4)
	flash_time = 0.05
	Sfx.play("shoot", -6.0, randf_range(0.95, 1.05) * (0.8 if pellets > 1 else 1.0))
	if fx != null and is_instance_valid(fx):
		fx.eject_shell(global_position + camera.global_transform.basis.x * 0.08 - camera.global_transform.basis.z * 0.2, camera.global_transform.basis.x, Vector3.UP)
	if Game.is_br():
		var mgr := get_node_or_null("/root/Main/BR")
		if mgr != null and mgr.has_method("noise"):
			mgr.noise(player.global_position, 80.0 if weapon_id == "sniper" else 55.0, player)

	var space_state := get_world_3d().direct_space_state
	var origin := camera.global_position
	var cam_basis := camera.global_transform.basis
	var any_hit := false
	var any_kill := false
	var sparks := 0
	var spread := _current_spread()
	var shot_dmg := 0.0
	var best_zone := "none"
	var last_hit_pos := Vector3.ZERO
	var living_hit := false

	for i in pellets:
		var dir := -cam_basis.z
		if spread > 0.0:
			var ang := deg_to_rad(spread)
			dir = (dir + cam_basis.x * randf_range(-ang, ang) + cam_basis.y * randf_range(-ang, ang)).normalized()
		var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * range_distance)
		query.exclude = [player.get_rid()]
		var result := space_state.intersect_ray(query)
		if i < 3:
			_spawn_tracer(result["position"] if not result.is_empty() else origin + dir * minf(range_distance, 80.0))
		if result.is_empty():
			continue

		var target: Object = result["collider"]
		if target.has_method("take_damage"):
			# 距離衰減：超過射程一半後傷害逐漸下降
			var dist := origin.distance_to(result["position"])
			var half := range_distance * 0.5
			var falloff := 1.0 if dist <= half else lerpf(1.0, 0.35, (dist - half) / half)
			var dmg := damage * damage_mult * equip_dmg * falloff
			var zone := "body"
			if Hitzone.is_living(target):
				zone = Hitzone.zone_of(target as Node3D, result["position"])
				dmg *= Hitzone.multiplier(zone, weapon_id)
				living_hit = true
			if zone == "head":
				best_zone = "head"
			elif best_zone != "head" and (best_zone == "none" or zone == "body"):
				best_zone = zone
			shot_dmg += dmg
			last_hit_pos = result["position"]
			if target.is_in_group("br_bots"):
				target.take_damage(dmg, player)
			else:
				target.take_damage(dmg)
			any_hit = true
			if target.get("is_dead") == true:
				any_kill = true
		elif sparks < 3:
			sparks += 1
			_spawn_spark(result["position"])
			if sparks == 1:
				_spawn_hole(result["position"], result["normal"])

	if any_hit:
		Game.hit_marker.emit(any_kill)
		Game.hit_detail.emit("body" if best_zone == "none" else best_zone, any_kill, shot_dmg, last_hit_pos)
		if living_hit and best_zone == "head":
			Game.record("headshots")
			Sfx.play("kill_ding" if any_kill else "hit_head", -4.0)
		elif any_kill:
			Sfx.play("kill_ding", -6.0)
		else:
			Sfx.play("hit", -8.0)


# 特效物件池：節點與資源只建立一次，之後重複使用（不會隨射擊不斷配置/釋放記憶體）
func _make_effect_pools() -> void:
	shared_box = BoxMesh.new()
	shared_box.size = Vector3.ONE
	hole_mesh = QuadMesh.new()
	hole_mesh.size = Vector2(0.16, 0.16)
	hole_mat = StandardMaterial3D.new()
	hole_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hole_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hole_mat.albedo_texture = hole_texture
	hole_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	spark_mesh = SphereMesh.new()
	spark_mesh.radius = 0.025
	spark_mesh.height = 0.05
	spark_mesh.radial_segments = 4
	spark_mesh.rings = 2


func _pooled_node(pool: Array, idx: int, limit: int, make: Callable) -> Node3D:
	if pool.size() < limit:
		var n: Node3D = make.call()
		n.top_level = true
		add_child(n)
		pool.append(n)
		return n
	return pool[idx % limit]


func _spawn_spark(pos: Vector3) -> void:
	var burst: CPUParticles3D = _pooled_node(spark_pool, spark_idx, SPARK_POOL, func() -> Node3D:
		var p := CPUParticles3D.new()
		p.emitting = false
		p.one_shot = true
		p.explosiveness = 1.0
		p.amount = 6
		p.lifetime = 0.45
		p.direction = Vector3.UP
		p.spread = 70.0
		p.initial_velocity_min = 1.0
		p.initial_velocity_max = 3.5
		p.gravity = Vector3(0.0, -9.0, 0.0)
		p.mesh = spark_mesh
		p.material_override = spark_material
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return p)
	spark_idx += 1
	burst.global_position = pos
	burst.restart()
	burst.emitting = true


func _spawn_hole(pos: Vector3, normal: Vector3) -> void:
	var q: MeshInstance3D = _pooled_node(hole_pool, hole_idx, HOLE_POOL, func() -> Node3D:
		var m := MeshInstance3D.new()
		m.mesh = hole_mesh
		m.material_override = hole_mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return m)
	hole_idx += 1
	q.global_position = pos + normal * 0.012
	var up := Vector3.UP if absf(normal.y) < 0.95 else Vector3.RIGHT
	q.look_at(pos + normal, up)
	q.rotate_object_local(Vector3.FORWARD, randf() * TAU)
	q.visible = true


func _spawn_tracer(to: Vector3) -> void:
	var from := flash_quad.global_position
	var dist := from.distance_to(to)
	if dist < 1.0:
		return
	var entry_node: MeshInstance3D = _pooled_node(tracer_pool, tracer_idx, TRACER_POOL, func() -> Node3D:
		var m := MeshInstance3D.new()
		m.mesh = shared_box
		m.material_override = tracer_material
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.visible = false
		return m)
	tracer_idx += 1
	entry_node.set_meta("ttl", 0.07)
	entry_node.scale = Vector3.ONE
	entry_node.global_position = (from + to) * 0.5
	entry_node.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
	entry_node.scale = Vector3(0.012, 0.012, dist)
	entry_node.visible = true


func _update_tracers(delta: float) -> void:
	for t in tracer_pool:
		var n := t as MeshInstance3D
		if not n.visible:
			continue
		var ttl: float = float(n.get_meta("ttl")) - delta
		n.set_meta("ttl", ttl)
		if ttl <= 0.0:
			n.visible = false
		else:
			var k := ttl / 0.07
			n.scale.x = 0.012 * k
			n.scale.y = 0.012 * k


func start_reload() -> void:
	if not armed or reload_left > 0.0 or current_ammo >= magazine_size or reserve_ammo <= 0:
		return
	reload_left = reload_time
	Sfx.play("reload", -4.0)
	update_ammo_ui()


func _finish_reload() -> void:
	if not armed:
		return
	var ammo_to_load: int = mini(magazine_size - current_ammo, reserve_ammo)
	current_ammo += ammo_to_load
	reserve_ammo -= ammo_to_load
	update_ammo_ui()


func _slot_text(i: int) -> String:
	var s: Dictionary = slots[i]
	var nm := "—" if s.is_empty() else str((WeaponDB.WEAPONS[s["id"]] as Dictionary)["name"]).get_slice(" ", 0)
	return ("▶%d %s" if i == active else " %d %s") % [i + 1, nm]


func update_ammo_ui() -> void:
	if ammo_label != null:
		if not armed:
			ammo_label.text = "徒手"
		elif reload_left > 0.0:
			ammo_label.text = "換彈中..."
		else:
			ammo_label.text = "子彈：%d / %d" % [current_ammo, reserve_ammo]
	if weapon_label == null:
		weapon_label = get_node_or_null("/root/Main/UI/WeaponLabel")
	if weapon_label != null:
		if Game.is_br():
			weapon_label.text = "%s　%s" % [_slot_text(0), _slot_text(1)]
		else:
			weapon_label.text = weapon_name
