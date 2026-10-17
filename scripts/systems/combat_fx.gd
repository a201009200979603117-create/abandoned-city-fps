extends Node3D
# 戰鬥視覺回饋：傷害數字、爆頭提示、受擊血花、彈殼拋出（皆使用物件池）

const TEXT_POOL: int = 14
const BLOOD_POOL: int = 6
const SHELL_POOL: int = 10

var texts: Array = []
var text_i: int = 0
var bloods: Array = []
var blood_i: int = 0
var shells: Array = []          # [MeshInstance3D, 速度, 剩餘時間]
var shell_i: int = 0
var shell_mesh: BoxMesh
var shell_mat: StandardMaterial3D
var blood_mesh: SphereMesh
var blood_mats: Dictionary = {}
var low: bool = false


func _ready() -> void:
	low = Save.effective_quality() == 0
	Game.hit_detail.connect(_on_hit_detail)
	shell_mesh = BoxMesh.new()
	shell_mesh.size = Vector3(0.018, 0.018, 0.055)
	shell_mat = StandardMaterial3D.new()
	shell_mat.albedo_color = Color(0.9, 0.7, 0.25)
	shell_mat.metallic = 0.8
	shell_mat.roughness = 0.35
	blood_mesh = SphereMesh.new()
	blood_mesh.radius = 0.03
	blood_mesh.height = 0.06
	blood_mesh.radial_segments = 4
	blood_mesh.rings = 2


func _process(delta: float) -> void:
	for s in shells:
		var n := s[0] as MeshInstance3D
		if not n.visible:
			continue
		s[2] -= delta
		if s[2] <= 0.0:
			n.visible = false
			continue
		var v: Vector3 = s[1]
		v.y -= 9.8 * delta
		n.global_position += v * delta
		n.rotate_x(delta * 14.0)
		if n.global_position.y <= 0.02:
			n.global_position.y = 0.02
			v.y = absf(v.y) * 0.25
			v.x *= 0.5
			v.z *= 0.5
		s[1] = v


func _on_hit_detail(zone: String, killed: bool, damage: float, pos: Vector3) -> void:
	number(pos, damage, zone, killed)
	if not low:
		blood(pos, zone, killed)


# ---------- 傷害數字 ----------

func number(pos: Vector3, dmg: float, zone: String, killed: bool) -> void:
	var l: Label3D
	if texts.size() < TEXT_POOL:
		l = Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.fixed_size = true
		l.pixel_size = 0.0011
		l.outline_size = 14
		l.top_level = true
		add_child(l)
		texts.append(l)
	else:
		l = texts[text_i % TEXT_POOL]
	text_i += 1
	l.visible = true
	l.text = str(int(round(dmg)))
	var col := Color(1.0, 1.0, 1.0)
	var fs := 46
	if zone == "head":
		col = Color(1.0, 0.78, 0.2)
		fs = 62
		l.text = "爆頭 " + l.text
	elif zone == "leg":
		col = Color(0.8, 0.85, 0.9)
		fs = 40
	if killed:
		col = Color(1.0, 0.3, 0.25)
		fs += 8
	l.font_size = fs
	l.modulate = col
	l.global_position = pos + Vector3(randf_range(-0.2, 0.2), 0.35, randf_range(-0.2, 0.2))
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "global_position:y", l.global_position.y + 0.9, 0.7).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.7).set_delay(0.25)
	tw.chain().tween_callback(func() -> void: l.visible = false)


# ---------- 血花 ----------

func blood(pos: Vector3, zone: String, killed: bool) -> void:
	var p: CPUParticles3D
	if bloods.size() < BLOOD_POOL:
		p = CPUParticles3D.new()
		p.emitting = false
		p.one_shot = true
		p.explosiveness = 1.0
		p.lifetime = 0.5
		p.direction = Vector3.UP
		p.spread = 80.0
		p.initial_velocity_min = 1.0
		p.initial_velocity_max = 3.5
		p.gravity = Vector3(0, -9.0, 0)
		p.mesh = blood_mesh
		p.top_level = true
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.45, 0.03, 0.03)
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		p.material_override = m
		add_child(p)
		bloods.append(p)
	else:
		p = bloods[blood_i % BLOOD_POOL]
	blood_i += 1
	p.amount = 14 if (killed or zone == "head") else 6
	p.global_position = pos
	p.restart()
	p.emitting = true


# ---------- 彈殼 ----------

func eject_shell(pos: Vector3, right: Vector3, up: Vector3) -> void:
	if low:
		return
	var s: Array
	if shells.size() < SHELL_POOL:
		var m := MeshInstance3D.new()
		m.mesh = shell_mesh
		m.material_override = shell_mat
		m.top_level = true
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)
		s = [m, Vector3.ZERO, 0.0]
		shells.append(s)
	else:
		s = shells[shell_i % SHELL_POOL]
	shell_i += 1
	var n := s[0] as MeshInstance3D
	n.visible = true
	n.global_position = pos
	n.rotation = Vector3(randf() * TAU, randf() * TAU, 0.0)
	s[1] = right * randf_range(1.2, 2.2) + up * randf_range(1.4, 2.4) + Vector3(randf_range(-0.3, 0.3), 0.0, randf_range(-0.3, 0.3))
	s[2] = 1.4
