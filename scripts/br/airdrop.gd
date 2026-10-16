extends Node3D
# 空投：大逃殺奪冠後從天而降的補給箱，打開可獲得裝備

signal landed
signal opened

enum State { FALLING, LANDED, OPEN }

var state: State = State.FALLING
var fall_speed: float = 14.0
var parachute: Node3D
var lid: Node3D
var beacon: MeshInstance3D
var glow: OmniLight3D
var hint: Label3D
var land_time: float = 0.0


func _ready() -> void:
	_build()
	position.y = 75.0


func _mat(c: Color, emission: float = 0.0, unshaded: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.6
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emission
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _build() -> void:
	var crate_mat := _mat(Color(0.85, 0.5, 0.1))
	var frame_mat := _mat(Color(0.15, 0.15, 0.17))
	var gold_mat := _mat(Color(1.0, 0.82, 0.3), 1.5)

	# 箱身
	_box(self, Vector3(1.4, 0.9, 1.4), Vector3(0.0, 0.45, 0.0), crate_mat)
	for sx in [-0.7, 0.7]:
		for sz in [-0.7, 0.7]:
			_box(self, Vector3(0.12, 0.95, 0.12), Vector3(sx, 0.47, sz), frame_mat)
	_box(self, Vector3(1.42, 0.12, 0.3), Vector3(0.0, 0.5, 0.0), frame_mat)

	# 箱蓋（以後側為轉軸）
	lid = Node3D.new()
	lid.position = Vector3(0.0, 0.9, 0.7)
	add_child(lid)
	_box(lid, Vector3(1.4, 0.12, 1.4), Vector3(0.0, 0.06, -0.7), crate_mat)
	_box(lid, Vector3(0.3, 0.14, 0.3), Vector3(0.0, 0.1, -0.7), gold_mat)

	# 降落傘
	parachute = Node3D.new()
	parachute.position = Vector3(0.0, 1.0, 0.0)
	add_child(parachute)
	var dome := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 2.6
	sph.height = 2.6
	sph.is_hemisphere = true
	dome.mesh = sph
	dome.material_override = _mat(Color(0.9, 0.9, 0.95))
	dome.position = Vector3(0.0, 4.0, 0.0)
	parachute.add_child(dome)
	var stripe := MeshInstance3D.new()
	var sph2 := SphereMesh.new()
	sph2.radius = 2.65
	sph2.height = 2.65
	sph2.is_hemisphere = true
	stripe.mesh = sph2
	stripe.material_override = _mat(Color(0.9, 0.2, 0.15))
	stripe.scale = Vector3(1.0, 1.0, 0.3)
	stripe.position = Vector3(0.0, 3.98, 0.0)
	parachute.add_child(stripe)
	for i in 8:
		var a := float(i) / 8.0 * TAU
		var line := _box(parachute, Vector3(0.025, 4.1, 0.025), Vector3(cos(a) * 1.3, 2.0, sin(a) * 1.3), frame_mat)
		line.rotation = Vector3(-sin(a) * 0.3, 0.0, cos(a) * 0.3)

	# 信標光柱
	beacon = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.35
	cyl.bottom_radius = 0.35
	cyl.height = 90.0
	beacon.mesh = cyl
	var bm := _mat(Color(1.0, 0.75, 0.2, 0.28), 1.2, true)
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beacon.material_override = bm
	beacon.position = Vector3(0.0, 45.0, 0.0)
	beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beacon)

	glow = OmniLight3D.new()
	glow.light_color = Color(1.0, 0.8, 0.4)
	glow.light_energy = 2.0
	glow.omni_range = 12.0
	glow.position = Vector3(0.0, 1.5, 0.0)
	add_child(glow)

	hint = Label3D.new()
	hint.text = "空投補給"
	hint.font_size = 48
	hint.pixel_size = 0.008
	hint.outline_size = 12
	hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hint.no_depth_test = true
	hint.position = Vector3(0.0, 2.4, 0.0)
	hint.modulate = Color(1.0, 0.85, 0.4)
	add_child(hint)


func _process(delta: float) -> void:
	match state:
		State.FALLING:
			var speed := fall_speed if position.y > 12.0 else 4.5
			position.y = maxf(position.y - speed * delta, 0.0)
			parachute.rotation.z = sin(Time.get_ticks_msec() * 0.003) * 0.05
			if position.y <= 0.0:
				_land()
		State.LANDED:
			land_time += delta
			hint.modulate.a = 0.7 + 0.3 * sin(land_time * 4.0)


func _land() -> void:
	state = State.LANDED
	parachute.visible = false
	Sfx.play("pickup", 0.0, 0.5)
	landed.emit()


func is_landed() -> bool:
	return state == State.LANDED


func open() -> void:
	if state != State.LANDED:
		return
	state = State.OPEN
	var tw := create_tween()
	tw.tween_property(lid, "rotation:x", -deg_to_rad(110.0), 0.5).set_ease(Tween.EASE_OUT)
	glow.light_energy = 8.0
	var burst := create_tween()
	burst.tween_property(glow, "light_energy", 3.0, 1.0)
	hint.text = "已開啟"
	Sfx.play("win", -4.0, 1.3)
	opened.emit()
