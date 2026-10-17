extends Node3D
# 酸液彈：吐酸殭屍發射的遠程攻擊。命中玩家造成傷害，落地會留下一小灘毒液

const TOXIC = preload("res://scripts/systems/toxic_zone.gd")

var velocity: Vector3 = Vector3.ZERO
var damage: float = 12.0
var life: float = 4.0
var owner_node: Node = null


func _ready() -> void:
	var mi := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.2
	sph.height = 0.4
	sph.radial_segments = 8
	sph.rings = 4
	mi.mesh = sph
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.45, 0.95, 0.2)
	m.emission_enabled = true
	m.emission = Color(0.4, 1.0, 0.15)
	m.emission_energy_multiplier = 2.0
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var l := OmniLight3D.new()
	l.light_color = Color(0.4, 1.0, 0.2)
	l.light_energy = 1.2
	l.omni_range = 4.0
	add_child(l)


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	velocity.y -= 4.0 * delta
	var from := global_position
	var to := from + velocity * delta
	var q := PhysicsRayQueryParameters3D.create(from, to)
	if owner_node is CollisionObject3D:
		q.exclude = [(owner_node as CollisionObject3D).get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		global_position = to
		return
	var col: Object = hit["collider"]
	if col is Node and (col as Node).is_in_group("player") and col.has_method("take_damage"):
		col.take_damage(damage, owner_node)
	_splash(hit["position"])
	queue_free()


func _splash(pos: Vector3) -> void:
	var host := get_tree().current_scene
	if host == null:
		return
	var zone := Node3D.new()
	zone.set_script(TOXIC)
	zone.set("radius", 1.9)
	zone.set("life", 3.5)
	zone.set("puddle", true)
	host.add_child(zone)
	zone.global_position = Vector3(pos.x, 0.0, pos.z)
	Sfx.play("hit", -10.0, 0.6)
