extends CharacterBody3D

enum Type { NORMAL, RUNNER, TANK }

const PICKUP_SCENE: PackedScene = preload("res://scenes/props/Pickup.tscn")

@export var move_speed: float = 2.6
@export var detection_range: float = 80.0
@export var attack_range: float = 1.6
@export var attack_damage: float = 10.0
@export var attack_interval: float = 1.0
@export var max_health: float = 60.0

var enemy_type: Type = Type.NORMAL
var points: int = 10
var body_scale: float = 1.0
var body_color: Color = Color(0.25, 0.32, 0.22)

var health: float = 60.0
var attack_timer: float = 0.5
var gravity: float = 9.8
var player: CharacterBody3D = null
var is_dead: bool = false
var side_dir: float = 1.0
var side_timer: float = 0.0
var body_material: StandardMaterial3D


# 生成前呼叫：依類型與波次決定能力
func setup(type: Type, wave: int) -> void:
	enemy_type = type
	var w := float(wave - 1)
	match type:
		Type.NORMAL:
			move_speed = 2.6
			max_health = 60.0 + 15.0 * w
			attack_damage = 10.0
			points = 10
		Type.RUNNER:
			move_speed = 4.6
			max_health = 35.0 + 8.0 * w
			attack_damage = 6.0
			attack_interval = 0.7
			points = 15
			body_scale = 0.9
			body_color = Color(0.55, 0.5, 0.2)
		Type.TANK:
			move_speed = 1.7
			max_health = 250.0 + 40.0 * w
			attack_damage = 22.0
			attack_interval = 1.4
			points = 40
			body_scale = 1.35
			body_color = Color(0.45, 0.15, 0.15)


func _ready() -> void:
	health = max_health
	add_to_group("enemies")
	scale = Vector3.ONE * body_scale
	_build_visuals()
	find_player()


func _build_visuals() -> void:
	var mesh_instance := get_node_or_null("MeshInstance3D") as MeshInstance3D
	body_material = StandardMaterial3D.new()
	body_material.albedo_color = body_color
	body_material.emission = Color.WHITE
	body_material.emission_enabled = true
	body_material.emission_energy_multiplier = 0.0
	if mesh_instance:
		mesh_instance.material_override = body_material

	var eye_material := StandardMaterial3D.new()
	eye_material.albedo_color = Color(1.0, 0.1, 0.1)
	eye_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for x in [-0.14, 0.14]:
		var eye := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.1, 0.06, 0.05)
		eye.mesh = box
		eye.material_override = eye_material
		eye.position = Vector3(x, 1.45, -0.37)
		add_child(eye)


func find_player() -> void:
	player = get_tree().get_first_node_in_group("player") as CharacterBody3D


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	attack_timer = maxf(attack_timer - delta, 0.0)

	if player == null or not is_instance_valid(player):
		find_player()

	var chasing := false
	if player != null and is_instance_valid(player) and not bool(player.get("is_dead")):
		var to_player := player.global_position - global_position
		to_player.y = 0.0
		var distance := to_player.length()

		if distance > 0.05:
			look_at(Vector3(player.global_position.x, global_position.y, player.global_position.z), Vector3.UP)

		if distance <= attack_range:
			chasing = true
			velocity.x = 0.0
			velocity.z = 0.0
			if attack_timer <= 0.0:
				if player.has_method("take_damage"):
					player.take_damage(attack_damage)
				attack_timer = attack_interval
		elif distance <= detection_range:
			chasing = true
			var direction := to_player.normalized()
			if side_timer > 0.0:
				side_timer -= delta
				direction = direction.rotated(Vector3.UP, side_dir * PI / 2.2)
			velocity.x = direction.x * move_speed
			velocity.z = direction.z * move_speed

	if not chasing:
		velocity.x = move_toward(velocity.x, 0.0, move_speed)
		velocity.z = move_toward(velocity.z, 0.0, move_speed)

	move_and_slide()

	# 卡牆時短暫繞行
	if is_on_wall() and side_timer <= 0.0:
		side_timer = 0.8
		side_dir = 1.0 if randf() < 0.5 else -1.0


func take_damage(damage: float) -> void:
	if is_dead:
		return

	health = maxf(health - damage, 0.0)
	_flash()

	if health <= 0.0:
		die()


func _flash() -> void:
	if body_material == null:
		return
	body_material.emission_energy_multiplier = 2.0
	var tw := create_tween()
	tw.tween_property(body_material, "emission_energy_multiplier", 0.0, 0.12)


func die() -> void:
	if is_dead:
		return

	is_dead = true
	remove_from_group("enemies")
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	Game.add_kill(points)
	Sfx.play("die", -4.0, randf_range(0.9, 1.1))

	var drop_chance := 0.35 if enemy_type == Type.NORMAL else 0.5
	if randf() < drop_chance:
		var pickup := PICKUP_SCENE.instantiate()
		pickup.set("pickup_type", randi_range(0, 1))
		pickup.position = Vector3(global_position.x, 1.0, global_position.z)
		get_tree().current_scene.add_child(pickup)

	var tw := create_tween()
	tw.tween_property(self, "rotation:x", -PI / 2.0, 0.3)
	tw.tween_interval(0.5)
	tw.tween_callback(queue_free)
