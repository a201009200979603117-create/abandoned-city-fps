extends Node3D
# 手榴彈：拋物線飛行、碰到地面/牆壁會反彈，引信 2.2 秒後爆炸（範圍傷害、可連鎖引爆油桶）

const RADIUS: float = 6.5
const MAX_DAMAGE: float = 135.0
const FUSE: float = 2.2

var velocity: Vector3 = Vector3.ZERO
var thrower: Node = null
var fuse_left: float = FUSE
var light: OmniLight3D
var mesh: MeshInstance3D
var done: bool = false
var blink_t: float = 0.0


func _ready() -> void:
	mesh = MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.09
	sph.height = 0.18
	sph.radial_segments = 8
	sph.rings = 4
	mesh.mesh = sph
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.15, 0.22, 0.12)
	m.roughness = 0.6
	mesh.material_override = m
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.2, 0.1)
	light.light_energy = 0.0
	light.omni_range = 2.5
	add_child(light)


func launch(v: Vector3, who: Node) -> void:
	velocity = v
	thrower = who


func _physics_process(delta: float) -> void:
	if done:
		return
	fuse_left -= delta
	blink_t += delta
	# 引信閃紅光，越接近爆炸越快
	var rate := lerpf(4.0, 16.0, 1.0 - clampf(fuse_left / FUSE, 0.0, 1.0))
	light.light_energy = 1.5 if fmod(blink_t * rate, 1.0) < 0.35 else 0.0
	if fuse_left <= 0.0:
		_explode()
		return
	velocity.y -= 14.0 * delta
	var from := global_position
	var to := from + velocity * delta
	var q := PhysicsRayQueryParameters3D.create(from, to)
	if thrower is CollisionObject3D:
		q.exclude = [(thrower as CollisionObject3D).get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		global_position = to
	else:
		# 反彈：沿法線反射並損失能量
		var n: Vector3 = hit["normal"]
		global_position = hit["position"] + n * 0.05
		velocity = velocity.bounce(n) * 0.45
		if velocity.length() < 1.2:
			velocity = Vector3.ZERO
		else:
			Sfx.play("step", -8.0, 1.6)
	rotate_x(delta * 6.0)


func _explode() -> void:
	done = true
	var pos := global_position + Vector3(0, 0.3, 0)
	Sfx.play("explosion", 0.0, randf_range(0.95, 1.1))
	_effect(pos)
	var tree := get_tree()
	var mgr := tree.current_scene.get_node_or_null("BR")
	if mgr != null and mgr.has_method("noise"):
		mgr.noise(global_position, 75.0, thrower)
	for group in ["br_bots", "enemies"]:
		for n in tree.get_nodes_in_group(group):
			var t := n as Node3D
			if t == null or bool(t.get("is_dead")):
				continue
			var d := t.global_position.distance_to(global_position)
			if d > RADIUS or not _clear(t):
				continue
			var dmg := MAX_DAMAGE * (1.0 - 0.7 * d / RADIUS)
			if group == "br_bots":
				t.take_damage(dmg, thrower)
			else:
				t.take_damage(dmg)
			if bool(t.get("is_dead")) and thrower != null and thrower.is_in_group("player"):
				Game.record("explosive_kills")
	var player := tree.get_first_node_in_group("player") as Node3D
	if player != null and not bool(player.get("is_dead")):
		var pd := player.global_position.distance_to(global_position)
		if pd < RADIUS and _clear(player):
			player.take_damage(MAX_DAMAGE * 0.8 * (1.0 - 0.7 * pd / RADIUS), thrower)
			if player.has_method("add_shake"):
				player.add_shake(clampf(1.2 - pd / RADIUS, 0.3, 1.0))
	for b in tree.get_nodes_in_group("barrels"):
		var other := b as Node3D
		if other != null and other.global_position.distance_to(global_position) < RADIUS * 0.8:
			other.explode(randf_range(0.05, 0.25))
	queue_free()


# 牆後不受傷：從爆心到目標胸口的視線不被擋住
func _clear(t: Node3D) -> bool:
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.3, 0), t.global_position + Vector3(0, 1.0, 0))
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or hit["collider"] == t


func _effect(pos: Vector3) -> void:
	var host := get_tree().current_scene
	if host == null:
		return
	var ball := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 2.0
	sph.radial_segments = 12
	sph.rings = 6
	ball.mesh = sph
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.6, 0.2, 0.85)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ball.material_override = m
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(ball)
	ball.global_position = pos
	ball.scale = Vector3.ONE * 0.4
	var tw := ball.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ball, "scale", Vector3.ONE * RADIUS * 0.5, 0.3).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.4)
	tw.chain().tween_callback(ball.queue_free)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.2)
	l.light_energy = 7.0
	l.omni_range = 12.0
	host.add_child(l)
	l.global_position = pos
	var lt := l.create_tween()
	lt.tween_property(l, "light_energy", 0.0, 0.45)
	lt.tween_callback(l.queue_free)
