extends Node3D
# 波次管理：依序生成敵人，清完一波後投放補給，最後一波清完即勝利

const ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/Enemy.tscn")
const PICKUP_SCENE: PackedScene = preload("res://scenes/props/Pickup.tscn")

@export var spawn_interval: float = 1.2
@export var first_wave_delay: float = 3.0
@export var wave_break: float = 5.0
@export var min_spawn_distance: float = 20.0
@export var max_spawn_distance: float = 32.0
@export var arena_half_size: float = 44.0

var wave_active: bool = false
var to_spawn: int = 0
var spawned_in_wave: int = 0
var spawn_timer: float = 0.0
var break_timer: float = 3.0


func _ready() -> void:
	break_timer = first_wave_delay


func _physics_process(delta: float) -> void:
	if not Game.is_playing():
		return

	var alive := get_tree().get_nodes_in_group("enemies").size()
	Game.enemies_remaining = alive + to_spawn

	if not wave_active:
		break_timer -= delta
		if break_timer <= 0.0:
			start_wave()
		return

	if to_spawn > 0:
		spawn_timer -= delta
		if spawn_timer <= 0.0 and alive < _max_alive():
			spawn_enemy()
			to_spawn -= 1
			spawn_timer = spawn_interval
	elif alive == 0:
		end_wave()


func _max_alive() -> int:
	return mini(6 + 2 * Game.wave, 14)


func start_wave() -> void:
	Game.wave += 1
	wave_active = true
	to_spawn = 5 + 3 * (Game.wave - 1)
	spawned_in_wave = 0
	spawn_timer = 0.0
	Sfx.play("wave")
	Game.wave_started.emit(Game.wave)


func end_wave() -> void:
	wave_active = false
	Game.wave_cleared.emit(Game.wave)
	if Game.wave >= Game.total_waves:
		Game.win()
		return
	break_timer = wave_break
	_drop_supplies()


func _pick_type() -> int:
	# 最後一波以坦克型開場
	if Game.wave >= Game.total_waves and spawned_in_wave == 0:
		return 2
	var r := randf()
	if Game.wave >= 3 and r < 0.15:
		return 2
	if Game.wave >= 2 and r < 0.40:
		return 1
	return 0


func spawn_enemy() -> void:
	var enemy := ENEMY_SCENE.instantiate()
	enemy.setup(_pick_type(), Game.wave)
	enemy.position = _find_spawn_position()
	get_tree().current_scene.add_child(enemy)
	spawned_in_wave += 1


func _find_spawn_position() -> Vector3:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var center := Vector3.ZERO
	if player != null:
		center = player.global_position

	var space := get_world_3d().direct_space_state
	var fallback := Vector3.ZERO
	for i in 12:
		var angle := randf() * TAU
		var dist := randf_range(min_spawn_distance, max_spawn_distance)
		var p := center + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		p.x = clampf(p.x, -arena_half_size, arena_half_size)
		p.z = clampf(p.z, -arena_half_size, arena_half_size)
		p.y = 0.1
		fallback = p

		# 從上往下射線：打到建築屋頂代表點位在建築內，換一個點
		var query := PhysicsRayQueryParameters3D.create(Vector3(p.x, 30.0, p.z), Vector3(p.x, -1.0, p.z))
		var hit := space.intersect_ray(query)
		if not hit.is_empty() and hit["position"].y < 0.5:
			return p
	return fallback


func _drop_supplies() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var center := Vector3.ZERO
	if player != null:
		center = player.global_position

	for type in [0, 1]:
		var pickup := PICKUP_SCENE.instantiate()
		pickup.set("pickup_type", type)
		var angle := randf() * TAU
		var dist := randf_range(3.0, 6.0)
		pickup.position = center + Vector3(cos(angle) * dist, 1.0, sin(angle) * dist)
		get_tree().current_scene.add_child(pickup)
