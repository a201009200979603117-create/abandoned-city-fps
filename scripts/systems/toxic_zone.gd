extends Node3D
# 毒氣區：範圍內的玩家與殭屍持續受傷。殭屍也會被毒傷，可以把牠們引進去

var radius: float = 5.5
var life: float = -1.0        # >0 = 存在秒數（酸液灘）
var puddle: bool = false
const TICK: float = 0.6
const PLAYER_DAMAGE: float = 5.0
const ENEMY_DAMAGE: float = 14.0

var tick_t: float = 0.0
var player: Node3D = null
var mat: StandardMaterial3D
var t: float = 0.0
var warned: bool = false


func _ready() -> void:
	add_to_group("toxic_zones")
	var cyl := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = 2.6
	cm.radial_segments = 24
	cm.cap_top = true
	cm.cap_bottom = false
	cyl.mesh = cm
	mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.9, 0.2, 0.16)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cyl.material_override = mat
	cyl.position.y = 1.3
	cyl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cyl)
	# 地面光圈
	var disc := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = radius
	dm.bottom_radius = radius
	dm.height = 0.03
	dm.radial_segments = 24
	disc.mesh = dm
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.4, 1.0, 0.25, 0.35)
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc.material_override = dmat
	disc.position.y = 0.04
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)
	# 冒泡的毒氣
	var p := CPUParticles3D.new()
	p.amount = 10 if Save.effective_quality() == 0 else 26
	p.lifetime = 3.0
	p.local_coords = true
	p.preprocess = 2.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius * 0.8
	p.direction = Vector3.UP
	p.spread = 15.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.7
	p.gravity = Vector3.ZERO
	var sm := SphereMesh.new()
	sm.radius = 0.55
	sm.height = 1.1
	sm.radial_segments = 6
	sm.rings = 3
	p.mesh = sm
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.4, 0.85, 0.2, 0.18)
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p.material_override = pm
	p.position.y = 0.4
	add_child(p)
	# 警示標籤
	var l := Label3D.new()
	l.text = "毒氣"
	l.font_size = 52
	l.pixel_size = 0.012
	l.outline_size = 12
	l.modulate = Color(0.55, 1.0, 0.35)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position.y = 3.4
	l.visibility_range_end = 45.0
	l.visible = not puddle
	add_child(l)


func _process(delta: float) -> void:
	t += delta
	if life > 0.0:
		life -= delta
		if life <= 0.0:
			queue_free()
			return
	mat.albedo_color.a = 0.13 + 0.05 * sin(t * 1.8)
	if not Game.is_playing():
		return
	tick_t -= delta
	if tick_t > 0.0:
		return
	tick_t = TICK
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node3D
	if player != null and not bool(player.get("is_dead")) and _inside(player):
		player.take_damage(PLAYER_DAMAGE, null)
		if not warned:
			warned = true
			Game.banner.emit("毒氣區！快離開")
	elif player != null and not _inside(player):
		warned = false
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Node3D
		if e != null and not bool(e.get("is_dead")) and _inside(e):
			e.take_damage(ENEMY_DAMAGE)


func _inside(n: Node3D) -> bool:
	var d := Vector2(n.global_position.x - global_position.x, n.global_position.z - global_position.z).length()
	return d < radius and n.global_position.y < 3.0
