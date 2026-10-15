
extends CharacterBody3D

const PICKUP_SCENE: PackedScene = preload("res://scenes/props/Pickup.tscn")

@export var move_speed: float = 2.5
@export var detection_range: float = 15.0
@export var attack_range: float = 1.5
@export var attack_damage: float = 10.0
@export var attack_interval: float = 1.0
@export var max_health: float = 100.0

var health: float = 100.0
var attack_timer: float = 0.0
var gravity: float = 9.8
var player: CharacterBody3D = null
var is_dead: bool = false


func _ready() -> void:
	health = max_health
	add_to_group("enemies")
	find_player()


func find_player() -> void:
	player = get_tree().get_first_node_in_group("player") as CharacterBody3D


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	if not is_on_floor():
		velocity.y -= gravity * delta
	if player == null or not is_instance_valid(player):
		find_player()
	if player != null and is_instance_valid(player):
		var distance := global_position.distance_to(player.global_position)

		if distance <= attack_range:
			velocity.x = 0.0
			velocity.z = 0.0

			attack_timer -= delta

			if attack_timer <= 0.0:
				if player.has_method("take_damage"):
					player.take_damage(attack_damage)
				attack_timer = attack_interval

		elif distance <= detection_range:
			var direction := player.global_position - global_position
			direction.y = 0.0
			direction = direction.normalized()

			velocity.x = direction.x * move_speed
			velocity.z = direction.z * move_speed
		else:
			velocity.x = move_toward(velocity.x, 0.0, move_speed)
			velocity.z = move_toward(velocity.z, 0.0, move_speed)
	else:
		velocity.x = move_toward(velocity.x, 0.0, move_speed)
		velocity.z = move_toward(velocity.z, 0.0, move_speed)

	move_and_slide()


func take_damage(damage: float) -> void:
	if is_dead:
		return

	health = maxf(health - damage, 0.0)
	print("敵人生命值：", health)

	if health <= 0.0:
		die()


func die() -> void:
	if is_dead:
		return

	is_dead = true
	print("敵人死亡！")

	if randf() < 0.5:
		var pickup = PICKUP_SCENE.instantiate()
		pickup.set("pickup_type", randi_range(0, 1))

		get_tree().current_scene.add_child(pickup)
		pickup.global_position = global_position + Vector3(0.0, 1.5, 0.0)
		pickup.update_pickup_color()

		print("敵人掉落補給品！")
	else:
		print("敵人沒有掉落補給品。")

	queue_free()
