extends Node3D
# 武器：殭屍模式依 Save.selected_weapon 載入；大逃殺模式為雙槍欄位，槍枝需在場上撿取。
# 皮膚取自 Save.selected_skin，裝備加成取自 Save.equipped。

const WeaponDB = preload("res://scripts/data/weapon_db.gd")

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
		"ammo": int(def["mag"]) if ammo < 0 else ammo,
		"reserve": int(float(def["reserve"]) * (1.0 + float(equip["ammo"]) / 100.0)) if reserve < 0 else reserve,
	}


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
	magazine_size = def["mag"]
	reload_time = maxf(float(def["reload"]) * (1.0 - float(equip["reload"]) / 100.0), 0.4)
	recoil_kick = def["recoil"]
	pellets = def["pellets"]
	spread_deg = def["spread"]
	automatic = def["auto"]
	zoom_fov = def["zoom"]
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

	fire_timer = maxf(fire_timer - delta, 0.0)

	if reload_left > 0.0:
		reload_left -= delta
		if reload_left <= 0.0:
			_finish_reload()

	if player.is_dead or not Game.is_playing():
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
	if want_fire and fire_timer <= 0.0 and reload_left <= 0.0 and sprint_pose < 0.5:
		shoot()


func _ads_held() -> bool:
	if Save.touch_mode:
		return touch_zoom
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func _update_zoom(delta: float) -> void:
	var want := armed and reload_left <= 0.0 and not bool(player.get("is_sprinting")) and _ads_held()
	ads = move_toward(ads, 1.0 if want else 0.0, delta * (6.0 if zoom_fov > 0.0 else 8.0))
	player.set("ads_factor", ads)
	var ads_fov := zoom_fov if zoom_fov > 0.0 else Save.fov * 0.82
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
	var sprint_target := 1.0 if (armed and bool(player.get("is_sprinting")) and moving > 1.0) else 0.0
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
	s *= lerpf(1.0, 0.35, ads)
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

	var space_state := get_world_3d().direct_space_state
	var origin := camera.global_position
	var cam_basis := camera.global_transform.basis
	var any_hit := false
	var any_kill := false
	var sparks := 0
	var spread := _current_spread()

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
		Sfx.play("hit", -8.0)


func _spawn_spark(pos: Vector3) -> void:
	var burst := CPUParticles3D.new()
	burst.emitting = true
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.amount = 6
	burst.lifetime = 0.45
	burst.direction = Vector3.UP
	burst.spread = 70.0
	burst.initial_velocity_min = 1.0
	burst.initial_velocity_max = 3.5
	burst.gravity = Vector3(0.0, -9.0, 0.0)
	var m := SphereMesh.new()
	m.radius = 0.025
	m.height = 0.05
	m.radial_segments = 4
	m.rings = 2
	burst.mesh = m
	burst.material_override = spark_material
	burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(burst)
	burst.global_position = pos
	get_tree().create_timer(0.7).timeout.connect(burst.queue_free)


func _spawn_hole(pos: Vector3, normal: Vector3) -> void:
	var q := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.16)
	q.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = hole_texture
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material_override = mat
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(q)
	q.global_position = pos + normal * 0.012
	var up := Vector3.UP if absf(normal.y) < 0.95 else Vector3.RIGHT
	q.look_at(pos + normal, up)
	q.rotate_object_local(Vector3.FORWARD, randf() * TAU)
	holes.append(q)
	if holes.size() > 40:
		var old: Node = holes.pop_front()
		if is_instance_valid(old):
			old.queue_free()


func _spawn_tracer(to: Vector3) -> void:
	var from := flash_quad.global_position
	var dist := from.distance_to(to)
	if dist < 1.0:
		return
	var t := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.012, 0.012, dist)
	t.mesh = box
	t.material_override = tracer_material
	t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(t)
	t.global_position = (from + to) * 0.5
	t.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
	var tw := t.create_tween()
	tw.tween_property(t, "scale", Vector3(0.0, 0.0, 1.0), 0.07)
	tw.tween_callback(t.queue_free)


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
