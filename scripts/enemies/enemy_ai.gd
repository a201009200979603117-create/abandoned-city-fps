extends CharacterBody3D

enum Type { NORMAL, RUNNER, TANK, BOSS, SPITTER, BLOATER }

const DeathAnim = preload("res://scripts/systems/death_anim.gd")
const Blast = preload("res://scripts/systems/blast.gd")
const AcidBlob = preload("res://scripts/enemies/acid_blob.gd")

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
var stuck_check_t: float = 0.0
var groan_timer: float = 0.0

# Boss 專用
var boss_name: String = ""
var slam_cd: float = 4.0
var charge_cd: float = 7.0
var slam_tele: float = 0.0
var charge_t: float = 0.0
var charge_dir: Vector3 = Vector3.ZERO
var charge_hit_cd: float = 0.0
var phase2: bool = false

# 吐酸殭屍
var spit_cd: float = 2.0
var spit_tele: float = 0.0
var strafe_dir: float = 1.0
var ring: MeshInstance3D = null
var stuck_pos: Vector3 = Vector3.ZERO
var stuck_count: int = 0

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
var anim_acc: float = 0.0


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
		Type.SPITTER:
			move_speed = 2.1
			max_health = 45.0 + 10.0 * w
			attack_damage = 6.0
			attack_range = 1.9
			points = 25
			body_scale = 0.95
		Type.BLOATER:
			move_speed = 1.8
			max_health = 100.0 + 15.0 * w
			attack_damage = 16.0
			points = 30
			body_scale = 1.12
		Type.BOSS:
			move_speed = 2.3
			max_health = 1800.0 + 350.0 * w
			attack_damage = 38.0
			attack_interval = 1.5
			attack_range = 2.8
			detection_range = 200.0
			points = 400
			body_scale = 2.1


func _ready() -> void:
	health = max_health
	add_to_group("enemies")
	scale = Vector3.ONE * body_scale
	anim_seed = randf() * TAU
	groan_timer = randf_range(1.5, 6.0)
	_build_visuals()
	_add_special_parts()
	if enemy_type == Type.BOSS:
		Game.boss_changed.emit(self)
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
		Type.BOSS:
			skin_col = Color(0.45, 0.2, 0.2)
			cloth_col = Color(0.22, 0.07, 0.12)
		Type.SPITTER:
			skin_col = Color(0.4, 0.6, 0.28)
			cloth_col = Color(0.14, 0.2, 0.12)
		Type.BLOATER:
			skin_col = Color(0.72, 0.7, 0.42)
			cloth_col = Color(0.32, 0.28, 0.2)
	body_color = cloth_col

	var skin := _tint_mat(skin_col)
	var cloth := _tint_mat(cloth_col)
	var pants := _tint_mat(pants_col)
	var dark := _shared_mat("dark", Color(0.06, 0.05, 0.05))
	var blood := _shared_mat("blood", Color(0.35, 0.02, 0.02))
	var hair := _shared_mat("hair", Color(0.1, 0.08, 0.06))
	var metal := _shared_mat("metal", Color(0.28, 0.29, 0.32), false, 0.8)
	var eye := _shared_mat("eye", Color(1.0, 0.1, 0.05) if enemy_type == Type.BOSS else (Color(0.5, 1.0, 0.2) if enemy_type == Type.SPITTER else Color(0.85, 0.7, 0.2)), true)
	var bone := _shared_mat("bone", Color(0.62, 0.58, 0.48))
	var grime := _shared_mat("grime", Color(0.07, 0.06, 0.05))

	visual = _pivot(self, Vector3.ZERO)
	var big := enemy_type == Type.TANK or enemy_type == Type.BOSS
	var wide := 1.18 if big else (0.9 if enemy_type == Type.RUNNER else (1.28 if enemy_type == Type.BLOATER else 1.0))

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
	if big:
		_add_box(head_pivot, Vector3(0.34, 0.12, 0.34), Vector3(0.0, 0.27, 0.0), metal)   # 頭盔
		_add_box(head_pivot, Vector3(0.3, 0.05, 0.05), Vector3(0.0, 0.2, -0.17), metal)
		if enemy_type == Type.BOSS:
			for sx in [-1.0, 1.0]:
				var horn := _add_box(head_pivot, Vector3(0.06, 0.26, 0.06), Vector3(sx * 0.15, 0.4, 0.0), bone)
				horn.rotation.z = -sx * 0.5
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
		if big:
			_add_box(shoulder, Vector3(0.22, 0.08, 0.22), Vector3(sx * 0.04, 0.0, 0.0), metal)
			if enemy_type == Type.BOSS:
				_add_box(shoulder, Vector3(0.05, 0.2, 0.05), Vector3(sx * 0.1, 0.1, 0.0), bone)   # 肩刺
	if big:
		_add_box(torso, Vector3(0.5, 0.36, 0.05), Vector3(0.0, 0.36, -0.15), metal)   # 胸甲
		_add_box(torso, Vector3(0.1, 0.1, 0.05), Vector3(0.0, 0.5, -0.17), blood)
		if enemy_type == Type.BOSS:
			for k in 4:
				_add_box(torso, Vector3(0.05, 0.22, 0.05), Vector3(-0.18 + 0.12 * k, 0.66, 0.1), bone)   # 背脊骨刺


# ---------- Boss 行為：震地波（可跳躍閃避）、衝鋒、殘血狂暴召喚小兵 ----------

# 回傳 true 代表本幀移動已由 Boss 技能接管
func _boss_update(delta: float, to_player: Vector3, distance: float) -> bool:
	slam_cd -= delta
	charge_cd -= delta
	charge_hit_cd = maxf(charge_hit_cd - delta, 0.0)
	if slam_tele > 0.0:
		slam_tele -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		_update_ring(1.0 - clampf(slam_tele / 0.9, 0.0, 1.0))
		if slam_tele <= 0.0:
			_boss_slam()
		return true
	if charge_t > 0.0:
		charge_t -= delta
		velocity.x = charge_dir.x * 11.0
		velocity.z = charge_dir.z * 11.0
		if distance < 3.2 and charge_hit_cd <= 0.0 and player != null and player.has_method("take_damage"):
			charge_hit_cd = 1.2
			player.take_damage(attack_damage * 1.2, self)
			player.velocity += charge_dir * 9.0 + Vector3.UP * 3.0
		return true
	if slam_cd <= 0.0 and distance < 12.0:
		slam_tele = 0.9
		slam_cd = 4.0 if phase2 else 6.0
		_show_ring()
		Sfx.play("roar", 0.0, 0.8)
		return true
	if charge_cd <= 0.0 and distance > 8.0 and distance < 30.0:
		charge_t = 1.1
		charge_dir = to_player.normalized()
		charge_cd = 7.0 if phase2 else 9.5
		Sfx.play("screech", 2.0, 0.55)
		return true
	return false


func _show_ring() -> void:
	if ring == null:
		ring = MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 1.0
		cyl.bottom_radius = 1.0
		cyl.height = 0.05
		ring.mesh = cyl
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1.0, 0.15, 0.1, 0.45)
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ring.material_override = m
		ring.top_level = true
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)
	ring.visible = true
	ring.global_position = Vector3(global_position.x, 0.08, global_position.z)
	ring.scale = Vector3(0.1, 1.0, 0.1)


func _update_ring(k: float) -> void:
	if ring == null:
		return
	var r := 0.5 + 7.5 * k
	ring.scale = Vector3(r, 1.0, r)
	var m := ring.material_override as StandardMaterial3D
	m.albedo_color.a = 0.25 + 0.35 * k


func _boss_slam() -> void:
	if ring != null:
		ring.visible = false
	Sfx.play("explosion", 0.0, 0.7)
	if player == null or not is_instance_valid(player):
		return
	var d := Vector2(player.global_position.x - global_position.x, player.global_position.z - global_position.z).length()
	if d < 8.0 and player.is_on_floor():   # 跳起來就能躲過
		player.take_damage(attack_damage * 0.9, self)
		var dir := (player.global_position - global_position)
		dir.y = 0.0
		player.velocity += dir.normalized() * 8.0 + Vector3.UP * 4.0
	if player.has_method("add_shake"):
		player.add_shake(clampf(1.0 - d / 20.0, 0.2, 1.0))


func _boss_enrage() -> void:
	phase2 = true
	move_speed *= 1.35
	Game.banner.emit("Boss 狂暴化！召喚了小兵")
	Sfx.play("roar", 2.0, 0.7)
	var sp := get_tree().get_first_node_in_group("enemy_spawner")
	if sp != null and sp.has_method("spawn_minions"):
		sp.spawn_minions(4, global_position)


# 吐酸殭屍的喉囊 / 膨脹者的腫脹肚子
func _add_special_parts() -> void:
	if enemy_type == Type.SPITTER:
		var sac := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.12
		sm.height = 0.24
		sm.radial_segments = 8
		sm.rings = 4
		sac.mesh = sm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.4, 0.9, 0.2)
		m.emission_enabled = true
		m.emission = Color(0.35, 1.0, 0.1)
		m.emission_energy_multiplier = 1.6
		sac.material_override = m
		sac.position = Vector3(0.0, -0.06, -0.06)
		sac.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		head_pivot.add_child(sac)
	elif enemy_type == Type.BLOATER:
		var belly := MeshInstance3D.new()
		var bs := SphereMesh.new()
		bs.radius = 0.36
		bs.height = 0.72
		bs.radial_segments = 10
		bs.rings = 5
		belly.mesh = bs
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color(0.62, 0.66, 0.22)
		bm.emission_enabled = true
		bm.emission = Color(0.5, 0.7, 0.1)
		bm.emission_energy_multiplier = 0.9
		belly.material_override = bm
		belly.scale = Vector3(1.05, 1.0, 0.9)
		belly.position = Vector3(0.0, 0.25, -0.2)
		belly.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		torso.add_child(belly)
		var pulse := belly.create_tween().set_loops()
		pulse.tween_property(bm, "emission_energy_multiplier", 1.8, 0.45)
		pulse.tween_property(bm, "emission_energy_multiplier", 0.5, 0.45)


# ---------- 吐酸殭屍：保持距離、停下蓄力後吐出酸液彈 ----------

func _has_los(to_pos: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.4, 0), to_pos + Vector3(0, 1.2, 0))
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or hit["collider"] == player


func _spitter_update(delta: float, to_player: Vector3, distance: float) -> bool:
	spit_cd -= delta
	if spit_tele > 0.0:
		spit_tele -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		if spit_tele <= 0.0:
			_spit()
		return true
	if distance < 8.0:
		var back := -to_player.normalized()
		velocity.x = back.x * move_speed * 0.9
		velocity.z = back.z * move_speed * 0.9
		return true
	if distance <= 22.0 and spit_cd <= 0.0 and player != null and _has_los(player.global_position):
		spit_tele = 0.55
		spit_cd = randf_range(2.4, 3.4)
		Sfx.play("screech", -8.0, 1.6)
		return true
	if distance <= 15.0:
		var side := to_player.normalized().cross(Vector3.UP) * strafe_dir
		velocity.x = side.x * move_speed * 0.5
		velocity.z = side.z * move_speed * 0.5
		if randf() < 0.01:
			strafe_dir = -strafe_dir
		return true
	return false


func _spit() -> void:
	if player == null or not is_instance_valid(player):
		return
	var blob := Node3D.new()
	blob.set_script(AcidBlob)
	get_tree().current_scene.add_child(blob)
	var from := global_position + Vector3(0, 1.4 * scale.y, 0)
	blob.global_position = from
	var target := player.global_position + Vector3(0, 1.1, 0) + Vector3(player.velocity.x, 0.0, player.velocity.z) * 0.35
	blob.set("velocity", (target - from).normalized() * 15.0)
	blob.set("owner_node", self)
	Sfx.play("hit", -4.0, 0.5)


# ---------- 膨脹者：死亡時爆炸（對周圍敵人與玩家造成傷害） ----------

func _bloater_burst() -> void:
	if visual != null:
		visual.visible = false
	Blast.burst(get_tree().current_scene, global_position + Vector3(0, 1.0, 0), 4.8, Color(0.6, 0.9, 0.2), 110.0, 32.0, self, 1.25)
	get_tree().create_timer(0.1).timeout.connect(queue_free)


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
	# 靠近玩家時不定時發出嘶吼（距離太遠的不播，音效由 Sfx 限制同時發聲數）
	groan_timer -= delta
	if groan_timer <= 0.0:
		groan_timer = randf_range(4.0, 9.0)
		if player != null and is_instance_valid(player) and global_position.distance_squared_to(player.global_position) < 1600.0:
			var kind: String = "screech" if (enemy_type == Type.RUNNER and randf() < 0.5) else ["groan1", "groan2", "groan3"].pick_random()
			Sfx.play3d(kind, global_position + Vector3(0, 1.5, 0), -4.0, randf_range(0.9, 1.15) * (0.8 if enemy_type == Type.TANK else 1.0))
	var frozen := slow_left > 0.0 and slow_mult <= 0.01
	var speed := move_speed * slow_mult

	if player == null or not is_instance_valid(player):
		find_player()

	var chasing := false
	var want_move := false
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
					player.take_damage(attack_damage, self)
				attack_timer = attack_interval / maxf(slow_mult, 0.2)
				attack_anim = 1.0
		elif enemy_type == Type.BOSS and _boss_update(delta, to_player, distance):
			chasing = true
		elif enemy_type == Type.SPITTER and distance <= detection_range and _spitter_update(delta, to_player, distance):
			chasing = true
		elif distance <= detection_range:
			chasing = true
			want_move = true
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
	# 動畫 LOD：遠處敵人降低動畫更新頻率，極遠時直接隱藏模型
	var d2 := 0.0
	if player != null and is_instance_valid(player):
		d2 = global_position.distance_squared_to(player.global_position)
	anim_acc += delta
	if d2 < 900.0 or (Engine.get_physics_frames() + get_instance_id()) % 3 == 0:
		_animate(anim_acc)
		anim_acc = 0.0
	if visual != null:
		visual.visible = d2 < 8100.0

	# 卡死偵測：想移動卻 2 秒內幾乎沒位移 → 先繞行，再失敗就重新傳送到開闊處
	if want_move:
		stuck_check_t += delta
		if stuck_check_t >= 2.0:
			if global_position.distance_to(stuck_pos) < 0.8:
				stuck_count += 1
				side_timer = 1.2
				side_dir = 1.0 if randf() < 0.5 else -1.0
				if stuck_count >= 2:
					stuck_count = 0
					var sp := get_tree().get_first_node_in_group("enemy_spawner")
					if sp != null and sp.has_method("relocate"):
						global_position = sp.relocate()
			else:
				stuck_count = 0
			stuck_pos = global_position
			stuck_check_t = 0.0
	else:
		stuck_check_t = 0.0
		stuck_pos = global_position

	# 卡牆時短暫繞行
	if is_on_wall() and side_timer <= 0.0:
		side_timer = 0.8
		side_dir = 1.0 if randf() < 0.5 else -1.0


func take_damage(damage: float) -> void:
	if is_dead:
		return

	health = maxf(health - damage, 0.0)
	flash_t = 0.12
	if enemy_type == Type.BOSS and not phase2 and health < max_health * 0.5 and health > 0.0:
		_boss_enrage()

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

	if enemy_type == Type.BOSS:
		Game.record("boss_kills")
		Game.add_xp(100)
		Game.boss_changed.emit(null)
		Game.banner.emit("Boss 擊敗！")
		Sfx.play("explosion", 0.0, 0.8)
		for k in 3:
			var bp := PICKUP_SCENE.instantiate()
			bp.set("pickup_type", k % 2)
			bp.position = Vector3(global_position.x + randf_range(-2.5, 2.5), 1.0, global_position.z + randf_range(-2.5, 2.5))
			get_tree().current_scene.add_child(bp)
		if ring != null:
			ring.queue_free()
	var drop_chance := 0.35 if enemy_type == Type.NORMAL else 0.5
	if randf() < drop_chance:
		var pickup := PICKUP_SCENE.instantiate()
		pickup.set("pickup_type", randi_range(0, 1))
		pickup.position = Vector3(global_position.x, 1.0, global_position.z)
		get_tree().current_scene.add_child(pickup)

	if enemy_type == Type.BLOATER:
		_bloater_burst()
		return
	var away := Vector3.ZERO
	if player != null and is_instance_valid(player):
		away = global_position - player.global_position
	var parts: Array = []
	parts.append_array(legs)
	parts.append_array(arms)
	parts.append_array(forearms)
	var heavy := enemy_type == Type.TANK or enemy_type == Type.BOSS
	DeathAnim.play(self, away, parts, heavy, 4.0 if enemy_type == Type.BOSS else 2.5)
