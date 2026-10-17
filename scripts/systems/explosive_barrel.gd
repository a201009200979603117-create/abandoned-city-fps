extends StaticBody3D
# 爆炸油桶：射擊或被爆炸波及就會引爆，對範圍內的敵人（以及玩家）造成傷害，並連鎖引爆附近的油桶

const RADIUS: float = 7.0
const MAX_DAMAGE: float = 240.0
const SELF_DAMAGE: float = 55.0

var health: float = 40.0
var exploded: bool = false
var body_mat: StandardMaterial3D


func _ready() -> void:
	add_to_group("barrels")
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.3
	cyl.bottom_radius = 0.3
	cyl.height = 0.9
	cyl.radial_segments = 10
	mi.mesh = cyl
	body_mat = StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.72, 0.12, 0.08)
	body_mat.roughness = 0.6
	body_mat.emission_enabled = true
	body_mat.emission = Color(0.6, 0.08, 0.04)
	body_mat.emission_energy_multiplier = 0.25
	mi.material_override = body_mat
	add_child(mi)
	# 黃色警示條
	for y in [-0.22, 0.22]:
		var band := MeshInstance3D.new()
		var bc := CylinderMesh.new()
		bc.top_radius = 0.305
		bc.bottom_radius = 0.305
		bc.height = 0.07
		bc.radial_segments = 10
		band.mesh = bc
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color(0.95, 0.8, 0.15)
		bm.emission_enabled = true
		bm.emission = Color(0.9, 0.7, 0.1)
		bm.emission_energy_multiplier = 0.3
		band.material_override = bm
		band.position.y = y
		add_child(band)
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.3
	shape.height = 0.9
	cs.shape = shape
	add_child(cs)


func take_damage(damage: float, _source: Node = null) -> void:
	if exploded:
		return
	health -= damage
	if health <= 0.0:
		explode()
	else:
		body_mat.emission_energy_multiplier = 1.6   # 受擊閃一下
		create_tween().tween_property(body_mat, "emission_energy_multiplier", 0.25, 0.2)


func explode(delay: float = 0.0) -> void:
	if exploded:
		return
	exploded = true
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
		if not is_inside_tree():
			return
	var pos := global_position + Vector3(0.0, 0.5, 0.0)
	Sfx.play("explosion", 0.0, randf_range(0.9, 1.1))
	_blast_effect(pos)
	var tree := get_tree()
	# 敵人 / AI 玩家
	for group in ["enemies", "br_bots"]:
		for n in tree.get_nodes_in_group(group):
			var t := n as Node3D
			if t == null or bool(t.get("is_dead")):
				continue
			var d := t.global_position.distance_to(global_position)
			if d > RADIUS:
				continue
			var dmg := MAX_DAMAGE * (1.0 - 0.65 * d / RADIUS)
			if group == "br_bots":
				t.take_damage(dmg, null)
			else:
				t.take_damage(dmg)
			if bool(t.get("is_dead")):
				Game.record("explosive_kills")
	# 玩家（較輕的自傷）
	var player := tree.get_first_node_in_group("player") as Node3D
	if player != null and not bool(player.get("is_dead")):
		var pd := player.global_position.distance_to(global_position)
		if pd < RADIUS:
			player.take_damage(SELF_DAMAGE * (1.0 - pd / RADIUS), null)
			if player.has_method("add_shake"):
				player.add_shake(clampf(1.2 - pd / RADIUS, 0.3, 1.0))
	# 連鎖
	for b in tree.get_nodes_in_group("barrels"):
		var other := b as Node3D
		if other != self and other != null and not bool(other.get("exploded")) and other.global_position.distance_to(global_position) < RADIUS * 0.7:
			other.explode(randf_range(0.1, 0.3))
	await get_tree().create_timer(0.05).timeout
	queue_free()


func _blast_effect(pos: Vector3) -> void:
	var host := get_tree().current_scene
	if host == null:
		return
	# 火球
	var ball := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 2.0
	sph.radial_segments = 12
	sph.rings = 6
	ball.mesh = sph
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.55, 0.15, 0.85)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ball.material_override = m
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(ball)
	ball.global_position = pos
	ball.scale = Vector3.ONE * 0.5
	var tw := ball.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ball, "scale", Vector3.ONE * RADIUS * 0.55, 0.35).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.45)
	tw.chain().tween_callback(ball.queue_free)
	# 閃光
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.2)
	light.light_energy = 8.0
	light.omni_range = 14.0
	host.add_child(light)
	light.global_position = pos
	var lt := light.create_tween()
	lt.tween_property(light, "light_energy", 0.0, 0.5)
	lt.tween_callback(light.queue_free)
	# 火花
	if Save.effective_quality() > 0:
		var p := CPUParticles3D.new()
		p.emitting = true
		p.one_shot = true
		p.explosiveness = 1.0
		p.amount = 30
		p.lifetime = 0.9
		p.direction = Vector3.UP
		p.spread = 80.0
		p.initial_velocity_min = 4.0
		p.initial_velocity_max = 11.0
		p.gravity = Vector3(0, -12.0, 0)
		var sm := SphereMesh.new()
		sm.radius = 0.06
		sm.height = 0.12
		sm.radial_segments = 4
		sm.rings = 2
		p.mesh = sm
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color(1.0, 0.6, 0.2)
		pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		p.material_override = pm
		host.add_child(p)
		p.global_position = pos
		get_tree().create_timer(1.2).timeout.connect(p.queue_free)
