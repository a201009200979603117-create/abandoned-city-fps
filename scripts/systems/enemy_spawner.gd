extends Node3D
# 波次管理：依序生成敵人，清完一波後投放補給，最後一波清完即勝利

const ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/Enemy.tscn")
const PICKUP_SCENE: PackedScene = preload("res://scenes/props/Pickup.tscn")

@export var spawn_interval: float = 1.2
@export var first_wave_delay: float = 3.0
@export var wave_break: float = 5.0
@export var min_spawn_distance: float = 22.0
@export var max_spawn_distance: float = 38.0
@export var arena_half_size: float = 94.0

var wave_active: bool = false
var to_spawn: int = 0
var spawned_in_wave: int = 0
var spawn_timer: float = 0.0
var break_timer: float = 3.0
var boss_pending: bool = false

const BOSS_NAMES: Dictionary = {3: "腐肉巨像", 4: "鐵顎屠夫", 5: "碎骨領主", 6: "疫病之母", 7: "毒霧君王", 8: "焚城惡魔", 9: "輻射巨獸", 10: "末日終焉者"}


func _ready() -> void:
	add_to_group("enemy_spawner")
	if Game.is_br():
		set_physics_process(false)   # 大逃殺模式沒有殭屍
		return
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

	if boss_pending:
		boss_pending = false
		spawn_boss()
	if to_spawn > 0:
		spawn_timer -= delta
		if spawn_timer <= 0.0 and alive < _max_alive():
			spawn_enemy()
			to_spawn -= 1
			spawn_timer = spawn_interval
	elif alive == 0:
		end_wave()


func _max_alive() -> int:
	return mini(6 + 2 * Game.wave + Game.level / 2, 18)


func start_wave() -> void:
	Game.wave += 1
	wave_active = true
	to_spawn = int(round(float(5 + 3 * (Game.wave - 1)) * float(Game.level_cfg["count_mult"])))
	spawned_in_wave = 0
	spawn_timer = 0.0
	boss_pending = Game.wave >= Game.total_waves and Game.level >= 3   # 最後一波出現 Boss
	Sfx.play("wave")
	Game.wave_started.emit(Game.wave)


func end_wave() -> void:
	wave_active = false
	Game.record("waves")
	Game.add_xp(20 + 5 * Game.wave)
	Game.score += 100 * Game.wave
	Save.save()
	Game.wave_cleared.emit(Game.wave)
	if Game.wave >= Game.total_waves:
		Game.win()
		return
	break_timer = wave_break
	_drop_supplies()


func spawn_boss() -> void:
	var boss := ENEMY_SCENE.instantiate()
	boss.setup(3, Game.wave)   # Type.BOSS
	boss.max_health *= float(Game.level_cfg["hp_mult"])
	boss.boss_name = str(BOSS_NAMES.get(Game.level, "變異巨獸"))
	boss.position = _find_spawn_position()
	get_tree().current_scene.add_child(boss)
	Game.banner.emit("Boss 出現：%s" % boss.boss_name)
	Sfx.play("siren", -2.0)
	Sfx.play("roar", 2.0, 0.6)


# Boss 狂暴時召喚小兵
func spawn_minions(n: int, center: Vector3) -> void:
	for i in n:
		var e := ENEMY_SCENE.instantiate()
		e.setup(0, Game.wave)
		var a := randf() * TAU
		e.position = Vector3(center.x + cos(a) * 5.0, 0.15, center.z + sin(a) * 5.0)
		get_tree().current_scene.add_child(e)


func _pick_type() -> int:
	# 特殊敵人：吐酸殭屍（第 2 波起）、膨脹者（第 3 波起），出現率隨關卡提高
	if Game.wave >= 2 and randf() < 0.08 + 0.015 * float(Game.level):
		return 4   # Type.SPITTER
	if Game.wave >= 3 and randf() < 0.05 + 0.01 * float(Game.level):
		return 5   # Type.BLOATER
	# 最後一波以坦克型開場
	if Game.wave >= Game.total_waves and spawned_in_wave == 0:
		return 2
	var tw: Array = Game.level_cfg["type_weights"]
	var w_normal: float = tw[0]
	var w_runner: float = tw[1] if Game.wave >= 2 else 0.0
	var w_tank: float = tw[2] if Game.wave >= 3 else 0.0
	var r := randf() * (w_normal + w_runner + w_tank)
	if r < w_tank:
		return 2
	if r < w_tank + w_runner:
		return 1
	return 0


func spawn_enemy() -> void:
	var enemy := ENEMY_SCENE.instantiate()
	enemy.setup(_pick_type(), Game.wave)
	enemy.max_health *= float(Game.level_cfg["hp_mult"])
	enemy.move_speed *= float(Game.level_cfg["speed_mult"])
	enemy.position = _find_spawn_position()
	get_tree().current_scene.add_child(enemy)
	spawned_in_wave += 1


func relocate() -> Vector3:
	return _find_spawn_position()


func _find_spawn_position() -> Vector3:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var center := Vector3.ZERO
	if player != null:
		center = player.global_position

	var space := get_world_3d().direct_space_state
	var best := Vector3.ZERO
	var best_score := -INF
	for i in 40:
		var angle := randf() * TAU
		var dist := randf_range(min_spawn_distance, max_spawn_distance)
		var p := center + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		p.x = clampf(p.x, -arena_half_size, arena_half_size)
		p.z = clampf(p.z, -arena_half_size, arena_half_size)

		# 從上往下射線：必須打到地面（非屋頂/物件頂部）
		var query := PhysicsRayQueryParameters3D.create(Vector3(p.x, 30.0, p.z), Vector3(p.x, -1.0, p.z))
		var hit := space.intersect_ray(query)
		if hit.is_empty() or hit["position"].y > 0.5:
			continue
		p.y = hit["position"].y + 0.15

		# 周圍必須有足夠空間（避免生在牆邊、箱子堆、車輛縫隙而卡死）
		var clearance := _clearance(space, p)
		if clearance < 3:
			continue
		# 優先選擇四周更開闊、且不在玩家視線內的點
		var score := float(clearance) * 2.0 + randf()
		if player != null:
			var los := PhysicsRayQueryParameters3D.create(player.global_position + Vector3(0, 1.5, 0), p + Vector3(0, 1.5, 0))
			los.exclude = [player.get_rid()]
			if not space.intersect_ray(los).is_empty():
				score += 3.0
		if score > best_score:
			best_score = score
			best = p
		if clearance >= 8 and score > 18.0:
			break
	if best_score > -INF:
		return best
	return _open_fallback(space, center)


# 以球形檢測 + 8 方向射線評估開闊度（回傳 0~8+：越大越開闊，0 代表被卡住）
func _clearance(space: PhysicsDirectSpaceState3D, p: Vector3) -> int:
	var sphere := SphereShape3D.new()
	sphere.radius = 0.55
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = sphere
	for h in [0.7, 1.4]:
		sq.transform = Transform3D(Basis.IDENTITY, p + Vector3(0.0, h, 0.0))
		if not space.intersect_shape(sq, 1).is_empty():
			return 0
	var open := 0
	for k in 8:
		var a := float(k) * TAU / 8.0
		var d := Vector3(cos(a), 0.0, sin(a))
		var rq := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.0, 0), p + Vector3(0, 1.0, 0) + d * 2.0)
		if space.intersect_ray(rq).is_empty():
			open += 1
	return open


func _open_fallback(space: PhysicsDirectSpaceState3D, center: Vector3) -> Vector3:
	# 找不到理想點：從場地中央向外螺旋搜尋任意空曠地面
	for i in 60:
		var a := randf() * TAU
		var r := randf_range(8.0, arena_half_size)
		var p := Vector3(cos(a) * r, 0.0, sin(a) * r)
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 30.0, p.z), Vector3(p.x, -1.0, p.z))
		var hit := space.intersect_ray(q)
		if hit.is_empty() or hit["position"].y > 0.5:
			continue
		p.y = hit["position"].y + 0.15
		if _clearance(space, p) >= 5:
			return p
	return Vector3(center.x + 25.0, 0.15, center.z)


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
