extends RefCounted
# 通用爆炸：視覺（火球 + 閃光）、音效、範圍傷害（敵人 / 玩家 / 連鎖油桶）


static func burst(host: Node, pos: Vector3, radius: float, color: Color, enemy_dmg: float, player_dmg: float, source: Node = null, pitch: float = 1.0) -> void:
	if host == null or not host.is_inside_tree():
		return
	Sfx.play("explosion", -2.0, pitch)
	_effect(host, pos, radius, color)
	var tree := host.get_tree()
	for n in tree.get_nodes_in_group("enemies"):
		var t := n as Node3D
		if t == null or bool(t.get("is_dead")) or t == source:
			continue
		var d := t.global_position.distance_to(pos)
		if d > radius:
			continue
		t.take_damage(enemy_dmg * (1.0 - 0.6 * d / radius))
		if bool(t.get("is_dead")):
			Game.record("explosive_kills")
	var player := tree.get_first_node_in_group("player") as Node3D
	if player != null and not bool(player.get("is_dead")):
		var pd := player.global_position.distance_to(pos)
		if pd < radius:
			player.take_damage(player_dmg * (1.0 - 0.6 * pd / radius), source)
			if player.has_method("add_shake"):
				player.add_shake(clampf(1.1 - pd / radius, 0.25, 1.0))
	for b in tree.get_nodes_in_group("barrels"):
		var other := b as Node3D
		if other != null and other.global_position.distance_to(pos) < radius:
			other.explode(randf_range(0.08, 0.25))


static func _effect(host: Node, pos: Vector3, radius: float, color: Color) -> void:
	var ball := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 2.0
	sph.radial_segments = 12
	sph.rings = 6
	ball.mesh = sph
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, 0.8)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ball.material_override = m
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(ball)
	ball.global_position = pos
	ball.scale = Vector3.ONE * 0.4
	var tw := ball.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ball, "scale", Vector3.ONE * radius * 0.6, 0.3).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.45)
	tw.chain().tween_callback(ball.queue_free)
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = 6.0
	l.omni_range = radius * 2.0
	host.add_child(l)
	l.global_position = pos
	var lt := l.create_tween()
	lt.tween_property(l, "light_energy", 0.0, 0.45)
	lt.tween_callback(l.queue_free)
