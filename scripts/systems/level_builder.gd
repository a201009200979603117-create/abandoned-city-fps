extends Node3D
# 以程式補完城市場景：霧氣、建築、車輛殘骸、路障、路燈與邊界牆

const BUILDING_SCENE: PackedScene = preload("res://scenes/props/building.tscn")

var rng := RandomNumberGenerator.new()
var lights: Array[OmniLight3D] = []
var light_base: Array[float] = []
var flicker_timer: float = 0.0


func _ready() -> void:
	rng.seed = 20260301
	_setup_environment()
	_setup_ground()
	_orient_existing_buildings()
	_build_buildings()
	_build_props()
	_build_street_lights()
	_build_boundary()
	Sfx.start_ambient()


func _process(delta: float) -> void:
	flicker_timer -= delta
	if flicker_timer > 0.0:
		return
	flicker_timer = 0.06
	for i in lights.size():
		if i % 3 == 0:
			lights[i].light_energy = light_base[i] * (0.1 if randf() < 0.08 else 1.0)


func _setup_environment() -> void:
	var we := get_parent().get_node_or_null("World/WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null:
		var env := we.environment
		env.fog_enabled = true
		env.fog_light_color = Color(0.30, 0.32, 0.36)
		env.fog_density = 0.018
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.25, 0.27, 0.33)
		env.ambient_light_energy = 0.7
	var sun := get_parent().get_node_or_null("World/DirectionalLight3D") as DirectionalLight3D
	if sun != null:
		sun.light_energy = 0.45
		sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)


func _make_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.95
	return m


func _setup_ground() -> void:
	var ground := get_parent().get_node_or_null("World/Ground/MeshInstance3D") as MeshInstance3D
	if ground != null:
		ground.material_override = _make_material(Color(0.16, 0.16, 0.15))
	var road := get_parent().get_node_or_null("World/CityMap/Road/MeshInstance3D") as MeshInstance3D
	if road != null:
		road.material_override = _make_material(Color(0.09, 0.09, 0.1))
		# 讓路面視覺高度與碰撞一致，並避免與地面共面閃爍
		road.position.y = 0.01


func _orient_existing_buildings() -> void:
	for node in get_parent().get_node("World/CityMap").get_children():
		if node.name.begins_with("Building"):
			_face_road(node as Node3D)


func _face_road(b: Node3D) -> void:
	b.rotation.y = PI / 2.0 if b.position.x < 0.0 else -PI / 2.0


func _build_buildings() -> void:
	var holder := get_parent().get_node("World/CityMap")
	# 道路兩側第一排（已存在 (-10,-15) (10,15) (-10,15)）
	var left_z: Array[float] = [-43.0, -29.0, -1.0, 29.0, 43.0]
	var right_z: Array[float] = [-43.0, -29.0, -15.0, -1.0, 29.0, 43.0]
	for z in left_z:
		_place_building(holder, Vector3(-10.0, 0.0, z))
	for z in right_z:
		_place_building(holder, Vector3(10.0, 0.0, z))
	# 第二排
	for z in [-42.0, -28.0, -14.0, 0.0, 14.0, 28.0, 42.0]:
		_place_building(holder, Vector3(-24.0, 0.0, z))
		_place_building(holder, Vector3(24.0, 0.0, z))


func _place_building(holder: Node, pos: Vector3) -> void:
	var b := BUILDING_SCENE.instantiate() as Node3D
	b.position = pos
	_face_road(b)
	holder.add_child(b)


func _add_box(pos: Vector3, size: Vector3, color: Color, yaw: float = 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = yaw
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.material_override = _make_material(color)
	body.add_child(mesh_instance)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	add_child(body)
	return body


func _near_spawn(x: float, z: float) -> bool:
	return Vector2(x, z).length() < 7.0


func _build_props() -> void:
	# 車輛殘骸（道路上）
	for i in 9:
		var x := rng.randf_range(-4.0, 4.0)
		var z := rng.randf_range(-42.0, 42.0)
		if _near_spawn(x, z):
			continue
		var yaw := rng.randf_range(-0.35, 0.35) + (PI if rng.randf() < 0.5 else 0.0)
		var tint := rng.randf_range(0.0, 1.0)
		var car := _add_box(Vector3(x, 0.55, z), Vector3(1.8, 0.7, 4.2), Color(0.28 + tint * 0.1, 0.16, 0.12), yaw)
		var cabin := MeshInstance3D.new()
		var cabin_mesh := BoxMesh.new()
		cabin_mesh.size = Vector3(1.6, 0.6, 2.0)
		cabin.mesh = cabin_mesh
		cabin.material_override = _make_material(Color(0.1, 0.11, 0.12))
		cabin.position = Vector3(0.0, 0.65, 0.2)
		car.add_child(cabin)
		var cabin_shape := CollisionShape3D.new()
		var cabin_box := BoxShape3D.new()
		cabin_box.size = cabin_mesh.size
		cabin_shape.shape = cabin_box
		cabin_shape.position = cabin.position
		car.add_child(cabin_shape)

	# 水泥路障
	for i in 12:
		var x := rng.randf_range(-5.0, 5.0)
		var z := rng.randf_range(-44.0, 44.0)
		if _near_spawn(x, z):
			continue
		_add_box(Vector3(x, 0.45, z), Vector3(2.4, 0.9, 0.5), Color(0.4, 0.4, 0.38), rng.randf_range(-0.8, 0.8))

	# 木箱堆與垃圾箱（巷弄）
	for i in 14:
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var x := side * rng.randf_range(15.0, 19.0)
		var z := rng.randf_range(-44.0, 44.0)
		var s := rng.randf_range(0.9, 1.4)
		_add_box(Vector3(x, s * 0.5, z), Vector3(s, s, s), Color(0.35, 0.26, 0.15), rng.randf_range(0.0, PI))
		if rng.randf() < 0.4:
			_add_box(Vector3(x + 1.6, 0.6, z), Vector3(1.8, 1.2, 1.0), Color(0.12, 0.25, 0.18), rng.randf_range(-0.3, 0.3))

	# 瓦礫
	for i in 14:
		var x := rng.randf_range(-44.0, 44.0)
		var z := rng.randf_range(-44.0, 44.0)
		if _near_spawn(x, z) or (absf(x) > 5.0 and absf(x) < 15.0) or absf(x) > 20.0:
			continue
		_add_box(Vector3(x, 0.2, z), Vector3(rng.randf_range(1.0, 2.2), 0.4, rng.randf_range(1.0, 2.2)), Color(0.3, 0.29, 0.27), rng.randf_range(0.0, PI))


func _build_street_lights() -> void:
	for z in [-36.0, -12.0, 12.0, 36.0]:
		for side in [-1.0, 1.0]:
			var x: float = side * 6.5
			var pole := MeshInstance3D.new()
			var pole_mesh := BoxMesh.new()
			pole_mesh.size = Vector3(0.15, 5.0, 0.15)
			pole.mesh = pole_mesh
			pole.material_override = _make_material(Color(0.1, 0.1, 0.1))
			pole.position = Vector3(x, 2.5, z)
			add_child(pole)

			var light := OmniLight3D.new()
			light.position = Vector3(x - side * 0.6, 5.0, z)
			light.light_color = Color(1.0, 0.85, 0.6)
			light.light_energy = 2.0
			light.omni_range = 12.0
			add_child(light)
			lights.append(light)
			light_base.append(2.0)


func _build_boundary() -> void:
	var body := StaticBody3D.new()
	for data in [
		[Vector3(0.0, 5.0, 50.5), Vector3(102.0, 10.0, 1.0)],
		[Vector3(0.0, 5.0, -50.5), Vector3(102.0, 10.0, 1.0)],
		[Vector3(50.5, 5.0, 0.0), Vector3(1.0, 10.0, 102.0)],
		[Vector3(-50.5, 5.0, 0.0), Vector3(1.0, 10.0, 102.0)],
	]:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = data[1]
		shape.shape = box
		shape.position = data[0]
		body.add_child(shape)
	add_child(body)
