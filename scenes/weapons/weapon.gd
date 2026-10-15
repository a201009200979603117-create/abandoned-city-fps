extends Node3D

@export var damage: float = 25.0
@export var fire_rate: float = 0.14
@export var range_distance: float = 100.0
@export var magazine_size: int = 30
@export var reserve_ammo: int = 90
@export var reload_time: float = 1.3
@export var recoil_kick: float = 0.012

var current_ammo: int = 30
var fire_timer: float = 0.0
var reload_left: float = 0.0
var kick: float = 0.0
var flash_time: float = 0.0

var camera: Camera3D
var head: Node3D
var player: CharacterBody3D
var base_position: Vector3
var flash_light: OmniLight3D
var spark_material: StandardMaterial3D

@onready var ammo_label: Label = get_node_or_null("/root/Main/UI/AmmoLabel")


func _ready() -> void:
	camera = get_parent() as Camera3D
	head = camera.get_parent() as Node3D
	player = head.get_parent() as CharacterBody3D
	current_ammo = magazine_size
	base_position = position

	spark_material = StandardMaterial3D.new()
	spark_material.albedo_color = Color(1.0, 0.8, 0.3)
	spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_build_model()
	update_ammo_ui()


func _build_model() -> void:
	_add_part(Vector3(0.07, 0.1, 0.45), Vector3(0.0, 0.0, 0.0), Color(0.12, 0.12, 0.13))
	_add_part(Vector3(0.035, 0.035, 0.3), Vector3(0.0, 0.02, -0.35), Color(0.06, 0.06, 0.07))
	_add_part(Vector3(0.06, 0.16, 0.08), Vector3(0.0, -0.12, 0.05), Color(0.1, 0.1, 0.1))
	_add_part(Vector3(0.05, 0.08, 0.1), Vector3(0.0, -0.08, 0.2), Color(0.18, 0.14, 0.1))

	flash_light = OmniLight3D.new()
	flash_light.position = Vector3(0.0, 0.02, -0.55)
	flash_light.light_color = Color(1.0, 0.8, 0.4)
	flash_light.light_energy = 3.0
	flash_light.omni_range = 6.0
	flash_light.visible = false
	add_child(flash_light)


func _add_part(size: Vector3, pos: Vector3, color: Color) -> void:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	m.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.6
	mat.metallic = 0.4
	m.material_override = mat
	m.position = pos
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)


func _process(delta: float) -> void:
	# 後座力恢復與槍口閃光
	kick = move_toward(kick, 0.0, delta * 9.0)
	position = base_position + Vector3(0.0, 0.012, 0.07) * kick
	if flash_time > 0.0:
		flash_time -= delta
		if flash_time <= 0.0:
			flash_light.visible = false

	fire_timer = maxf(fire_timer - delta, 0.0)

	if reload_left > 0.0:
		reload_left -= delta
		if reload_left <= 0.0:
			_finish_reload()

	if player.is_dead or not Game.is_playing():
		return

	if Input.is_action_just_pressed("reload"):
		start_reload()

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return

	if Input.is_key_pressed(KEY_F) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if fire_timer <= 0.0 and reload_left <= 0.0:
			shoot()


func shoot() -> void:
	fire_timer = fire_rate

	if current_ammo <= 0:
		Sfx.play("empty")
		fire_timer = 0.3
		start_reload()
		return

	current_ammo -= 1
	update_ammo_ui()

	kick = 1.0
	head.rotation.x = minf(head.rotation.x + recoil_kick, deg_to_rad(85.0))
	flash_light.visible = true
	flash_time = 0.04
	Sfx.play("shoot", -6.0, randf_range(0.95, 1.05))

	var space_state := get_world_3d().direct_space_state
	var origin := camera.global_position
	var end := origin - camera.global_transform.basis.z * range_distance

	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.exclude = [player.get_rid()]

	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return

	var target: Object = result["collider"]
	if target.has_method("take_damage"):
		target.take_damage(damage)
		Game.hit_marker.emit(target.get("is_dead") == true)
		Sfx.play("hit", -8.0)
	else:
		_spawn_spark(result["position"])


func _spawn_spark(pos: Vector3) -> void:
	var spark := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.06
	sphere.height = 0.12
	spark.mesh = sphere
	spark.material_override = spark_material
	spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(spark)
	spark.global_position = pos
	var tw := spark.create_tween()
	tw.tween_property(spark, "scale", Vector3.ZERO, 0.15)
	tw.tween_callback(spark.queue_free)


func start_reload() -> void:
	if reload_left > 0.0 or current_ammo >= magazine_size or reserve_ammo <= 0:
		return
	reload_left = reload_time
	Sfx.play("reload", -4.0)
	update_ammo_ui()


func _finish_reload() -> void:
	var ammo_to_load: int = mini(magazine_size - current_ammo, reserve_ammo)
	current_ammo += ammo_to_load
	reserve_ammo -= ammo_to_load
	update_ammo_ui()


func update_ammo_ui() -> void:
	if ammo_label == null:
		return
	if reload_left > 0.0:
		ammo_label.text = "換彈中..."
	else:
		ammo_label.text = "子彈：%d / %d" % [current_ammo, reserve_ammo]
