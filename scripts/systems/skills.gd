extends Node
# 技能系統：Z X C V B 施放，冷卻、效果與特效

const SkillDB = preload("res://scripts/data/skill_db.gd")

var cooldowns: Dictionary = {}
var cooldown_max: Dictionary = {}
var player: CharacterBody3D
var weapon: Node3D
var buff_left: float = 0.0


func _ready() -> void:
	player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	weapon = player.get_node_or_null("Head/Camera3D/Weapon") as Node3D
	for id in SkillDB.ORDER:
		cooldowns[id] = 0.0
		cooldown_max[id] = 1.0


func cooldown_fraction(id: String) -> float:
	return clampf(float(cooldowns[id]) / maxf(float(cooldown_max[id]), 0.01), 0.0, 1.0)


func _process(delta: float) -> void:
	if not Game.is_playing():
		return
	for id in SkillDB.ORDER:
		cooldowns[id] = maxf(float(cooldowns[id]) - delta, 0.0)
	if buff_left > 0.0:
		buff_left -= delta
		if buff_left <= 0.0:
			_end_frenzy()


func _unhandled_input(event: InputEvent) -> void:
	if Game.is_br() or not Game.is_playing() or player == null or player.is_dead:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var idx: int = SkillDB.KEYS.find(event.physical_keycode)
		if idx >= 0:
			cast(SkillDB.ORDER[idx])


func cast(id: String) -> void:
	var level := Game.skill_level(id)
	if level <= 0 or float(cooldowns[id]) > 0.0:
		return
	var evo := Game.is_evolved(id)
	var cd := SkillDB.cooldown(id, level, evo)
	cooldowns[id] = cd
	cooldown_max[id] = cd
	Game.skill_cast.emit(id, evo)
	match id:
		"shockwave":
			_shockwave(level, evo)
		"heal":
			_heal(level, evo)
		"grenade":
			_grenade(level, evo)
		"freeze":
			_freeze(level, evo)
		"frenzy":
			_frenzy(level, evo)


# ---------- 輔助 ----------

func _enemies_in(center: Vector3, radius: float) -> Array:
	var result: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		var n := e as Node3D
		if n != null and n.global_position.distance_to(center) <= radius:
			result.append(n)
	return result


func _hurt(e: Node, dmg: float) -> void:
	e.take_damage(dmg)
	Game.hit_marker.emit(e.get("is_dead") == true)


# 擴散圓環特效
func _ring(center: Vector3, radius: float, color: Color, duration: float = 0.45) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 0.15
	cyl.radial_segments = 32
	mi.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(mi)
	mi.global_position = Vector3(center.x, 0.1, center.z)
	mi.scale = Vector3(0.5, 1.0, 0.5)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(radius, 1.0, radius), duration).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, duration)
	tw.chain().tween_callback(mi.queue_free)


# 爆炸球體特效
func _blast(center: Vector3, radius: float, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 16
	sphere.rings = 8
	mi.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(mi)
	mi.global_position = center
	mi.scale = Vector3.ONE * 0.3
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 6.0
	light.omni_range = radius * 2.0
	mi.add_child(light)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * radius, 0.3).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.4)
	tw.tween_property(light, "light_energy", 0.0, 0.4)
	tw.chain().tween_callback(mi.queue_free)


# ---------- 技能 ----------

func _shockwave(level: int, evo: bool) -> void:
	var radius := 20.0 if evo else 7.0 + 2.0 * level
	var dmg := 260.0 if evo else 35.0 + 25.0 * level
	var col := Color(1.0, 0.55, 0.15)
	var origin := player.global_position
	Sfx.play("wave", 2.0, 0.7)
	_ring(origin, radius, col, 0.5)
	if evo:
		_ring(origin, radius * 0.6, Color(1.0, 0.85, 0.3), 0.35)
	for e in _enemies_in(origin, radius):
		var away: Vector3 = e.global_position - origin
		away.y = 0.0
		var falloff := 1.0 - 0.5 * clampf(away.length() / radius, 0.0, 1.0)
		e.apply_knockback(away.normalized() * (20.0 if evo else 12.0))
		if evo:
			e.apply_slow(0.0, 2.5)
		_hurt(e, dmg * falloff)


func _heal(level: int, evo: bool) -> void:
	Sfx.play("pickup", 0.0, 0.7)
	_ring(player.global_position, 2.5, Color(0.3, 1.0, 0.5), 0.6)
	if evo:
		player.heal(player.max_health)
		player.start_regen(8.0, 6.0)
		_ring(player.global_position, 5.0, Color(0.6, 1.0, 0.7), 0.9)
	else:
		player.heal(25.0 + 15.0 * level)


func _grenade(level: int, evo: bool) -> void:
	var cam := player.get_node("Head/Camera3D") as Camera3D
	var origin := cam.global_position
	var dir := -cam.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * 45.0)
	query.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	var target: Vector3 = origin + dir * 45.0
	if not hit.is_empty():
		target = hit["position"]
	target.y = maxf(target.y, 0.2)

	var radius := 9.0 if evo else 4.0 + level
	var dmg := 300.0 if evo else 90.0 + 50.0 * level
	var count := 4 if evo else 1

	# 飛行中的榴彈
	var nade := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.24
	nade.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.5, 0.1)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	nade.material_override = mat
	get_tree().current_scene.add_child(nade)
	nade.global_position = origin + dir * 0.6 + Vector3(0.2, -0.3, 0.0)
	var flight := clampf(origin.distance_to(target) / 40.0, 0.25, 0.8)
	var tw := nade.create_tween()
	tw.tween_property(nade, "global_position", target, flight)
	tw.tween_callback(nade.queue_free)
	tw.tween_callback(_explode.bind(target, radius, dmg))
	for i in range(1, count):
		var offset := Vector3(randf_range(-6.0, 6.0), 0.0, randf_range(-6.0, 6.0))
		get_tree().create_timer(flight + 0.3 * i).timeout.connect(_explode.bind(target + offset, radius, dmg))


func _explode(pos: Vector3, radius: float, dmg: float) -> void:
	if not is_inside_tree():
		return
	Sfx.play("die", 2.0, 0.5)
	_blast(pos + Vector3(0.0, 0.5, 0.0), radius, Color(1.0, 0.5, 0.15))
	for e in _enemies_in(pos, radius):
		var dist: float = e.global_position.distance_to(pos)
		var falloff := 1.0 - 0.6 * clampf(dist / radius, 0.0, 1.0)
		var away: Vector3 = e.global_position - pos
		away.y = 0.0
		e.apply_knockback(away.normalized() * 8.0)
		_hurt(e, dmg * falloff)


func _freeze(level: int, evo: bool) -> void:
	var radius := 45.0 if evo else 30.0
	var duration := 5.0 if evo else 3.0 + level
	var mult := 0.0 if evo else 0.35
	Sfx.play("wave", 0.0, 1.6)
	_ring(player.global_position, minf(radius, 30.0), Color(0.5, 0.85, 1.0), 0.6)
	for e in _enemies_in(player.global_position, radius):
		e.apply_slow(mult, duration)
		if evo:
			_hurt(e, 50.0)


func _frenzy(level: int, evo: bool) -> void:
	Sfx.play("wave", 0.0, 1.3)
	_ring(player.global_position, 3.0, Color(1.0, 0.25, 0.3), 0.5)
	if weapon == null:
		return
	if evo:
		buff_left = 14.0
		weapon.fire_mult = 0.4
		weapon.damage_mult = 2.2
		weapon.infinite_ammo = true
	else:
		buff_left = 6.0 + 2.0 * level
		weapon.fire_mult = 0.6
		weapon.damage_mult = 1.3 + 0.1 * level
		weapon.infinite_ammo = false


func _end_frenzy() -> void:
	if weapon == null:
		return
	weapon.fire_mult = 1.0
	weapon.damage_mult = 1.0
	weapon.infinite_ammo = false
