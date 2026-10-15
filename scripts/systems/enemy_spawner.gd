extends Node3D

const ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/Enemy.tscn")

@export var spawn_interval: float = 5.0
@export var max_enemies: int = 5
@export var spawn_radius: float = 15.0

var spawn_timer: float = 0.0

func _process(delta: float) -> void:
	spawn_timer += delta

	if spawn_timer >= spawn_interval:
		spawn_timer = 0.0
		spawn_enemy()

func spawn_enemy() -> void:
	var enemies = get_tree().get_nodes_in_group("enemies")

	if enemies.size() >= max_enemies:
		return

	var enemy = ENEMY_SCENE.instantiate()
	get_tree().current_scene.add_child(enemy)

	var angle = randf() * TAU
	var distance = randf_range(8.0, spawn_radius)

	var spawn_position = global_position + Vector3(
		cos(angle) * distance,
		0.0,
		sin(angle) * distance
	)

	enemy.global_position = spawn_position
	enemy.add_to_group("enemies")

	print("生成敵人：", spawn_position)