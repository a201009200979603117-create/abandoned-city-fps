extends CharacterBody3D

enum Type { NORMAL, RUNNER, TANK }

# 所有敵人共用的資源
static var box_cache: Dictionary = {}
static var head_mesh: SphereMesh
static var shared_mats: Dictionary = {}

const PICKUP_SCENE: PackedScene = preload("res://scenes/props/Pickup.tscn")

const CLOTH_COLORS: Array = [
	Color(0.2, 0.2, 0.18), Color(0.16, 0.18, 0.22), Color(0.26, 0.19, 0.15),
	Color(0.22, 0.22, 0.23), Color(0.14, 0.19, 0.16), Color(0.27, 0.24, 0.18),
]
const SKIN_COLORS: Array = [
	Color(0.36, 0.4, 0.33), Color(0.4, 0.42, 0.34), Color(0.33, 0.37, 0.34), Color(0.42, 0.38, 0.3),
]

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

# 狀態效果（技能使用）
var slow_mult: float = 1.0
var slow_left: float = 0.0
var knock: Vector3 = Vector3.ZERO
var flash_t: float = 0.0
var last_tint: int = -1

# 模型與動畫
var tint_mats: Array = []
var visual: Node3D
var torso: Node3D
var head_pivot: Node3D
var legs: Array = []
var arms: Array = []
var forearms: Array = []
var walk_phase: float = 0.0
var anim_seed: float = 0.0
var attack_anim: float = 0.0
var lean: float = 0.0


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
			body_scale = 0.92
		Type.TANK:
			move_speed = 1.7
			max_health = 250.0 + 40.0 * w
			attack_damage = 22.0
			attack_interval = 1.4
			points = 40
			body_scale = 1.3


func _ready() -> void:
	health = max_health
	add_to_group("enemies")
	scale = Vector3.ONE * body_scale
	anim_seed = randf() * TAU
	_build_visuals()
	find_player()


# ---------- 模型 ----------

static func _box_mesh(size: Vector3) -> BoxMesh:
	if not box_cache.has(size):
		var m := BoxMesh.new()
		m.size = size
		box_cache[size] = m
	return box_cache[size]


static func _shared_mat(key: String, color: Color, unshaded: bool = false, metal: float = 0.0) -> StandardMaterial3D:
	if not shared_mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.metallic = metal
		m.roughness = 0.5 if metal > 0.0 else 0.9
		if unshaded:
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		shared_mats[key] = m
	return shared_mats[key]


func _tint_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	m.emission_enabled = true
	m.emission = Color.WHITE
	m.emission_energy_multiplier = 0.0
	tint_mats.append(m)
	return m


func _add_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _box_mesh(size)
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _build_visuals() -> void:
	var old_mesh := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if old_mesh:
		old_mesh.visible = false

	var skin_col: Color = SKIN_COLORS[randi() % SKIN_COLORS.size()]
	var cloth_col: Color = CLOTH_COLORS[randi() % CLOTH_COLORS.size()]
	var pants_col := Color(0.16, 0.17, 0.2).lerp(cloth_col, 0.2)
	match enemy_type:
		Type.RUNNER:
			skin_col = skin_col.lerp(Color(0.7, 0.62, 0.35), 0.35)
			cloth_col = cloth_col.lerp(Color(0.5, 0.42, 0.15), 0.3)
		Type.TANK:
			skin_col = skin_col.lerp(Color(0.6, 0.3, 0.28), 0.45)
			cloth_col = Color(0.3, 0.12, 0.12)
	body_color = cloth_col

	var skin := _tint_mat(skin_col)
	var cloth := _tint_mat(cloth_col)
	var pants := _tint_mat(pants_col)
	var dark := _shared_mat("dark", Color(0.06, 0.05, 0.05))
	var blood := _shared_mat("blood", Color(0.35, 0.02, 0.02))
	var hair := _shared_mat("hair", Color(0.1, 0.08, 0.06))
	var metal := _shared_mat("metal", Color(0.28, 0.29, 0.32), false, 0.8)
	var eye := _shared_mat("eye", Color(0.85, 0.7, 0.2), true)
	var bone := _shared_mat("bone", Color(0.62, 0.58, 0.48))
	var grime := _shared_mat("grime", Color(0.07, 0.06, 0.05))

	visual = _pivot(self, Vector3.ZERO)
	var wide := 1.18 if enemy_type == Type.TANK else (0.9 if enemy_type == Type.RUNNER else 1.0)

	# 腿
	for sx in [-1.0, 1.0]:
		var leg := _pivot(visual, Vector3(sx * 0.11 * wide, 0.82, 0.0))
		_add_box(leg, Vector3(0.16 * wide, 0.5, 0.18), Vector3(0.0, -0.25, 0.0), pants)
		_add_box(leg, Vector3(0.17 * wide, 0.08, 0.27), Vector3(0.0, -0.53, -0.04), dark)
		legs.append(leg)
	# 破損的褲管
	_add_box(visual, Vector3(0.1, 0.1, 0.02), Vector3(0.1, 0.5, -0.095), skin)

	# 軀幹
	torso = _pivot(visual, Vector3(0.0, 0.82, 0.0))
	lean = -0.42 if enemy_type == Type.RUNNER else -0.12
	torso.rotation.x = lean
	_add_box(torso, Vector3(0.46 * wide, 0.6, 0.26), Vector3(0.0, 0.31, 0.0), cloth)
	_add_box(torso, Vector3(0.48 * wide, 0.08, 0.28), Vector3(0.0, 0.04, 0.0), dark)
	# 血跡與撕裂的衣服
	_add_box(torso, Vector3(0.2, 0.18, 0.01), Vector3(0.07, 0.36, -0.135), blood)
	_add_box(torso, Vector3(0.12, 0.1, 0.01), Vector3(-0.1, 0.18, -0.135), blood)
	_add_box(torso, Vector3(0.12, 0.14, 0.02), Vector3(-0.1, 0.1, -0.12), skin)

	# 腐爛：外露肋骨、破洞與髒污
	for rb in 3:
		_add_box(torso, Vector3(0.18, 0.025, 0.02), Vector3(-0.08, 0.22 + rb * 0.06, -0.135), bone)
	_add_box(torso, Vector3(0.18, 0.2, 0.012), Vector3(-0.08, 0.28, -0.131), grime)
	_add_box(torso, Vector3(0.5 * wide, 0.12, 0.3), Vector3(0.0, 0.06, 0.0), grime)   # 下襬髒污
	_add_box(torso, Vector3(0.08, 0.3, 0.015), Vector3(0.16, 0.3, -0.135), grime)       # 垂落的破布
	_add_box(visual, Vector3(0.17, 0.26, 0.19), Vector3(-0.11 * wide, 0.34, 0.0), grime)  # 腿部髒污

	# 頭
	head_pivot = _pivot(torso, Vector3(0.0, 0.66, 0.0))
	if head_mesh == null:
		head_mesh = SphereMesh.new()
		head_mesh.radius = 0.16
		head_mesh.height = 0.34
		head_mesh.radial_segments = 12
		head_mesh.rings = 6
	var head := MeshInstance3D.new()
	head.mesh = head_mesh
	head.material_override = skin
	head.position = Vector3(0.0, 0.14, -0.02)
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	head_pivot.add_child(head)
	_add_box(head_pivot, Vector3(0.12, 0.05, 0.12), Vector3(0.0, -0.01, -0.07), blood)   # 張開的下顎
	for sx in [-1.0, 1.0]:
		_add_box(head_pivot, Vector3(0.05, 0.035, 0.02), Vector3(sx * 0.065, 0.17, -0.15), eye)
		_add_box(head_pivot, Vector3(0.07, 0.025, 0.02), Vector3(sx * 0.065, 0.2, -0.145), dark)  # 眼窩陰影
	if enemy_type == Type.TANK:
		_add_box(head_pivot, Vector3(0.34, 0.12, 0.34), Vector3(0.0, 0.27, 0.0), metal)   # 頭盔
		_add_box(head_pivot, Vector3(0.3, 0.05, 0.05), Vector3(0.0, 0.2, -0.17), metal)
	else:
		_add_box(head_pivot, Vector3(0.22, 0.05, 0.2), Vector3(0.0, 0.28, 0.01), hair)
		_add_box(head_pivot, Vector3(0.05, 0.12, 0.1), Vector3(0.12, 0.2, 0.05), hair)

	# 手臂（殭屍姿勢：向前伸直）
	for sx in [-1.0, 1.0]:
		var shoulder := _pivot(torso, Vector3(sx * 0.3 * wide, 0.52, 0.0))
		_add_box(shoulder, Vector3(0.13, 0.3, 0.13), Vector3(0.0, -0.15, 0.0), cloth)
		var elbow := _pivot(shoulder, Vector3(0.0, -0.3, 0.0))
		_add_box(elbow, Vector3(0.1, 0.28, 0.1), Vector3(0.0, -0.14, 0.0), skin)
		_add_box(elbow, Vector3(0.09, 0.09, 0.07), Vector3(0.0, -0.31, 0.0), skin)
		_add_box(elbow, Vector3(0.02, 0.07, 0.02), Vector3(sx * 0.03, -0.37, -0.01), dark)   # 指甲
		arms.append(shoulder)
		forearms.append(elbow)
		if enemy_type == Type.TANK:
			_add_box(shoulder, Vector3(0.22, 0.08, 0.22), Vector3(sx * 0.04, 0.0, 0.0), metal)
	if enemy_type == Type.TANK:
		_add_box(torso, Vector3(0.5, 0.36, 0.05), Vector3(0.0, 0.36, -0.15), metal)   # 胸甲
		_add_box(torso, Vector3(0.1, 0.1, 0.05), Vector3(0.0, 0.5, -0.17), blood)


func find_player() -> void:
	player = get_tree().get_first_node_in_group("player") as CharacterBody3D


# ---------- 技能狀態 ----------

func apply_slow(mult: float, duration: float) -> void:
	if is_dead:
		return
	if slow_left <= 0.0 or mult <= slow_mult:
		slow_mult = mult
	slow_left = maxf(slow_left, duration)


func apply_knockback(v: Vector3) -> void:
	if is_dead:
		return
	knock = v


func _update_tint() -> void:
	var key := 0
	var energy := 0.0
	var col := Color.WHITE
	if flash_t > 0.0:
		energy = flash_t / 0.12 * 2.0
		key = 1000 + int(energy * 10.0)
	elif slow_left > 0.0:
		col = Color(0.4, 0.8, 1.0)
		energy = 0.9 if slow_mult <= 0.01 else 0.45
		key = 1 + int(energy * 10.0)
	if key == last_tint:
		return
	last_tint = key
	for m in tint_mats:
		var mat: StandardMaterial3D = m
		mat.emission = col
		mat.emission_energy_multiplier = energy


func _animate(delta: float) -> void:
	var spd := Vector2(velocity.x, velocity.z).length()
	var k := clampf(spd / 2.0, 0.0, 1.0)
	walk_phase += spd * delta * 2.4
	attack_anim = maxf(attack_anim - delta * 2.5, 0.0)
	var atk := sin(attack_anim * PI)
	var t := Time.get_ticks_msec() * 0.001 + anim_seed

	for i in legs.size():
		(legs[i] as Node3D).rotation.x = sin(walk_phase + float(i) * PI) * 0.75 * k
	var runner := enemy_type == Type.RUNNER
	for i in arms.size():
		var a := arms[i] as Node3D
		var f := forearms[i] as Node3D
		if runner and k > 0.2:
			a.rotation.x = 0.5 + sin(walk_phase + float(i) * PI) * 1.0 - atk * 0.9
			f.rotation.x = 1.0
		else:
			a.rotation.x = 1.35 + sin(t * 2.0 + float(i) * PI) * 0.08 - atk * 0.9
			f.rotation.x = 0.3 + sin(t * 3.0 + float(i)) * 0.06
	torso.rotation.x = lean - atk * 0.3
	torso.position.y = 0.82 + absf(sin(walk_phase)) * 0.04 * k
	head_pivot.rotation.z = sin(t * 1.6) * 0.12
	head_pivot.rotation.x = 0.15 + sin(t * 2.3) * 0.05
	visual.position.y = 0.0


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	if flash_t > 0.0:
		flash_t = maxf(flash_t - delta, 0.0)
	if slow_left > 0.0:
		slow_left -= delta
		if slow_left <= 0.0:
			slow_mult = 1.0
	_update_tint()

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	attack_timer = maxf(attack_timer - delta, 0.0)
	var frozen := slow_left > 0.0 and slow_mult <= 0.01
	var speed := move_speed * slow_mult

	if player == null or not is_instance_valid(player):
		find_player()

	var chasing := false
	if player != null and is_instance_valid(player) and not bool(player.get("is_dead")) and not frozen:
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
				attack_timer = attack_interval / maxf(slow_mult, 0.2)
				attack_anim = 1.0
		elif distance <= detection_range:
			chasing = true
			var direction := to_player.normalized()
			if side_timer > 0.0:
				side_timer -= delta
				direction = direction.rotated(Vector3.UP, side_dir * PI / 2.2)
			velocity.x = direction.x * speed
			velocity.z = direction.z * speed

	if not chasing:
		velocity.x = move_toward(velocity.x, 0.0, move_speed)
		velocity.z = move_toward(velocity.z, 0.0, move_speed)

	# 擊退
	if knock.length_squared() > 0.04:
		velocity.x += knock.x
		velocity.z += knock.z
		knock = knock.move_toward(Vector3.ZERO, 40.0 * delta)

	move_and_slide()
	_animate(delta)

	# 卡牆時短暫繞行
	if is_on_wall() and side_timer <= 0.0:
		side_timer = 0.8
		side_dir = 1.0 if randf() < 0.5 else -1.0


func take_damage(damage: float) -> void:
	if is_dead:
		return

	health = maxf(health - damage, 0.0)
	flash_t = 0.12

	if health <= 0.0:
		die()


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
