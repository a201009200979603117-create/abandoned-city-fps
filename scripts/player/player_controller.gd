extends CharacterBody3D

const GrenadeScript = preload("res://scripts/br/grenade.gd")

signal damaged(amount: float)
signal hit_from(source_pos: Vector3)   # 受擊來源（HUD 顯示方向指示）

@export var max_health: float = 100.0
@export var move_speed: float = 4.2
@export var sprint_multiplier: float = 1.55
@export var jump_velocity: float = 4.2
@export var accel: float = 38.0
@export var friction: float = 30.0
@export var air_accel: float = 6.0
@export var mouse_sensitivity: float = 0.002

var health: float = 100.0
var is_dead: bool = false
var gravity: float = 14.0
var was_on_floor: bool = true
var fall_speed: float = 0.0
var land_dip: float = 0.0
var shake: float = 0.0
var sway_roll: float = 0.0
var ads_factor: float = 0.0   # 0=腰射 1=完全瞄準（由武器更新）
var is_sprinting: bool = false
var step_timer: float = 0.0
var bob_time: float = 0.0
var crouching: bool = false
var armor: float = 0.0
var head_y: float = 1.6
var regen_rate: float = 0.0
var regen_left: float = 0.0

# 大逃殺道具
const MAX_ITEMS: int = 4
const MAX_SHIELD: float = 50.0
var grenades: int = 0
var medkits: int = 0
var plates: int = 0
var shield: float = 0.0
var use_t: float = 0.0          # 正在使用道具的剩餘時間（醫療包 3 秒、護甲板 1.5 秒）
var use_kind: String = ""
var grenade_cd: float = 0.0

# 跳傘
var skydiving: bool = false
var chute_open: bool = false
var dive_time: float = 0.0
var far_before: float = 130.0
var env_ref: Environment = null
var fog_before: float = 0.0
signal landed

@onready var health_label: Label = get_node_or_null("/root/Main/UI/HealthLabel")
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var head_base_y: float = $Head.position.y
@onready var body_shape: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	var eq := Save.equip_totals()
	max_health += float(eq["hp"])
	move_speed *= 1.0 + float(eq["speed"]) / 100.0
	armor = float(eq["armor"]) / 100.0
	health = max_health
	head_y = head_base_y
	camera.fov = Save.fov
	update_health_ui()


# 陀螺儀轉視角（弧度）
func apply_look_rad(yaw: float, pitch: float) -> void:
	if is_dead or not Game.is_playing():
		return
	rotate_y(yaw)
	head.rotate_x(pitch)
	head.rotation.x = clampf(head.rotation.x, deg_to_rad(-85.0), deg_to_rad(85.0))


# 觸控轉視角（由 TouchControls 呼叫）
func apply_look(rel: Vector2) -> void:
	if is_dead or not Game.is_playing():
		return
	rotate_y(-rel.x * mouse_sensitivity * Save.sensitivity)
	head.rotate_x(-rel.y * mouse_sensitivity * Save.sensitivity)
	head.rotation.x = clampf(head.rotation.x, deg_to_rad(-85.0), deg_to_rad(85.0))


func heal(amount: float) -> void:
	if is_dead:
		return
	health = minf(health + amount, max_health)
	update_health_ui()


func start_regen(rate: float, duration: float) -> void:
	regen_rate = rate
	regen_left = duration


func _unhandled_input(event: InputEvent) -> void:
	if is_dead or not Game.is_playing():
		return

	if event is InputEventMouseMotion and not Save.touch_mode:
		var k := Save.sensitivity * lerpf(1.0, 0.6, ads_factor)
		rotate_y(-event.relative.x * mouse_sensitivity * k)
		head.rotate_x(-event.relative.y * mouse_sensitivity * k)
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-85.0), deg_to_rad(85.0))


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	if regen_left > 0.0:
		regen_left -= delta
		heal(regen_rate * delta)

	if skydiving:
		_skydive_physics(delta)
		return

	_update_items(delta)

	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	_update_crouch(delta)
	var speed := move_speed
	var sprinting := Input.is_action_pressed("sprint") and input_dir.y < 0.0 and not crouching and ads_factor < 0.3
	is_sprinting = sprinting
	if sprinting:
		speed *= sprint_multiplier
	elif crouching:
		speed *= 0.5
	speed *= lerpf(1.0, 0.62, ads_factor)
	if use_t > 0.0:
		speed *= 0.45   # 使用道具時行動緩慢

	# 加減速：地面有慣性、空中幾乎無法改向
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if direction != Vector3.ZERO:
		var a := accel if is_on_floor() else air_accel
		horizontal = horizontal.move_toward(direction * speed, a * delta)
	elif is_on_floor():
		horizontal = horizontal.move_toward(Vector3.ZERO, friction * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if not is_on_floor():
		fall_speed = velocity.y
	move_and_slide()
	if is_on_floor() and not was_on_floor and fall_speed < -3.0:
		land_dip = clampf(-fall_speed * 0.012, 0.03, 0.18)
		Sfx.play("step", -4.0, 0.7)
	was_on_floor = is_on_floor()
	land_dip = move_toward(land_dip, 0.0, delta * 0.5)
	shake = move_toward(shake, 0.0, delta * 3.0)
	_update_camera_fx(delta, input_dir)
	_update_head_bob(delta, horizontal.length() > 0.5 and is_on_floor(), sprinting)


# 鏡頭側傾（掃射/側移）與受擊震動
func _update_camera_fx(delta: float, input_dir: Vector2) -> void:
	var target_roll := -input_dir.x * 0.025 * (1.0 - ads_factor)
	sway_roll = lerpf(sway_roll, target_roll, minf(delta * 8.0, 1.0))
	camera.rotation.z = sway_roll + randf_range(-1.0, 1.0) * shake * 0.03
	camera.rotation.x = randf_range(-1.0, 1.0) * shake * 0.02


func add_shake(amount: float) -> void:
	shake = minf(shake + amount, 1.0)


func _update_crouch(delta: float) -> void:
	crouching = Input.is_action_pressed("crouch")
	var target_y := head_base_y - (0.6 if crouching else 0.0)
	head_y = lerpf(head_y, target_y, minf(delta * 12.0, 1.0))
	var capsule := body_shape.shape as CapsuleShape3D
	var h := 1.2 if crouching else 1.8
	capsule.height = lerpf(capsule.height, h, minf(delta * 14.0, 1.0))
	body_shape.position.y = capsule.height * 0.5


func _update_head_bob(delta: float, moving: bool, sprinting: bool) -> void:
	if moving:
		var rate := 13.0 if sprinting else 9.0
		bob_time += delta * rate
		head.position.y = head_y - land_dip + sin(bob_time) * 0.04 * (1.0 - ads_factor * 0.8)
		step_timer -= delta
		if step_timer <= 0.0:
			Sfx.play("step", -12.0, randf_range(0.85, 1.1))
			step_timer = 0.3 if sprinting else 0.42
	else:
		head.position.y = lerpf(head.position.y, head_y - land_dip, delta * 10.0)
		step_timer = 0.0


func take_damage(damage: float, source: Node = null) -> void:
	if is_dead:
		return
	if source != null and source.get("bot_name") != null:
		Game.killed_by = str(source.get("bot_name"))
	elif source == null and Game.is_br():
		Game.killed_by = "安全區"

	if skydiving:
		return
	var remaining := damage * (1.0 - armor)
	if shield > 0.0:
		var absorbed := minf(shield, remaining)
		shield -= absorbed
		remaining -= absorbed
	if use_t > 0.0:
		_cancel_use()   # 受傷會打斷使用道具
	health = maxf(health - remaining, 0.0)
	update_health_ui()
	damaged.emit(damage)
	if source is Node3D:
		hit_from.emit((source as Node3D).global_position)
	add_shake(clampf(damage / 25.0, 0.3, 1.0))
	Sfx.play("hurt", -2.0)

	if health <= 0.0:
		die()


# ---------- 道具（大逃殺） ----------

func add_item(kind: String, n: int = 1) -> bool:
	match kind:
		"grenade":
			if grenades >= MAX_ITEMS:
				return false
			grenades = mini(grenades + n, MAX_ITEMS)
		"medkit":
			if medkits >= MAX_ITEMS:
				return false
			medkits = mini(medkits + n, MAX_ITEMS)
		"plate":
			if plates >= MAX_ITEMS:
				return false
			plates = mini(plates + n, MAX_ITEMS)
	return true


func _update_items(delta: float) -> void:
	grenade_cd = maxf(grenade_cd - delta, 0.0)
	if use_t > 0.0:
		use_t -= delta
		if use_t <= 0.0:
			_finish_use()
	if not Game.is_br():
		return
	if Input.is_action_just_pressed("grenade"):
		throw_grenade()
	if Input.is_action_just_pressed("medkit"):
		start_use("medkit")
	if Input.is_action_just_pressed("plate"):
		start_use("plate")


func throw_grenade() -> void:
	if grenades <= 0 or grenade_cd > 0.0 or is_dead or not Game.is_playing():
		return
	grenades -= 1
	grenade_cd = 0.8
	var g := Node3D.new()
	g.set_script(GrenadeScript)
	get_tree().current_scene.add_child(g)
	var fwd := -camera.global_transform.basis.z
	g.global_position = camera.global_position + fwd * 0.6 + Vector3(0, -0.15, 0)
	g.launch(fwd * 17.0 + Vector3.UP * 4.5 + Vector3(velocity.x, 0.0, velocity.z) * 0.5, self)
	Sfx.play("grenade_pin", 0.0, 0.8)


func start_use(kind: String) -> void:
	if use_t > 0.0 or is_dead:
		return
	if kind == "medkit":
		if medkits <= 0 or health >= max_health:
			return
		use_t = 3.0
	elif kind == "plate":
		if plates <= 0 or shield >= MAX_SHIELD:
			return
		use_t = 1.5
	else:
		return
	use_kind = kind
	Game.banner.emit("使用中…" + ("（醫療包）" if kind == "medkit" else "（護甲板）"))


func _cancel_use() -> void:
	use_t = 0.0
	use_kind = ""


func _finish_use() -> void:
	if use_kind == "medkit" and medkits > 0:
		medkits -= 1
		heal(max_health * 0.6)
		Sfx.play("pickup", 0.0, 1.2)
	elif use_kind == "plate" and plates > 0:
		plates -= 1
		shield = minf(shield + 25.0, MAX_SHIELD)
		Sfx.play("pickup", 0.0, 0.9)
	use_kind = ""


# ---------- 跳傘 ----------

func start_skydive() -> void:
	skydiving = true
	far_before = camera.far
	var we := get_node_or_null("/root/Main/World/WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null:
		env_ref = we.environment
		fog_before = env_ref.fog_density
	chute_open = false
	dive_time = 0.0
	velocity = Vector3.ZERO
	is_sprinting = false


func _skydive_physics(delta: float) -> void:
	dive_time += delta
	var alt := global_position.y
	# 手動開傘（跳躍鍵）或低於 45 公尺自動開傘
	if not chute_open and ((Input.is_action_just_pressed("jump") and dive_time > 1.0) or alt < 50.0):
		chute_open = true
		Sfx.play("pickup", 0.0, 0.6)
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var look_down := clampf(-head.rotation.x / deg_to_rad(60.0), 0.0, 1.0)   # 低頭俯衝更快
	var h_speed := 11.0 if chute_open else (16.0 + 10.0 * look_down)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(direction * h_speed, 28.0 * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if chute_open:
		velocity.y = move_toward(velocity.y, -5.5, 30.0 * delta)
	else:
		velocity.y = maxf(velocity.y - 14.0 * delta, -22.0 - 7.0 * look_down)
	camera.fov = lerpf(camera.fov, Save.fov + (14.0 if not chute_open else 4.0), minf(delta * 3.0, 1.0))
	camera.far = 320.0   # 高空需要看得更遠
	if env_ref != null:
		# 高空霧氣變淡才看得到地面，越接近地面越濃
		env_ref.fog_density = fog_before * lerpf(1.0, 0.08, clampf((alt - 40.0) / 120.0, 0.0, 1.0))
	move_and_slide()
	if is_on_floor() and dive_time > 0.5:
		skydiving = false
		chute_open = false
		camera.fov = Save.fov
		camera.far = far_before
		if env_ref != null:
			env_ref.fog_density = fog_before
		velocity = Vector3.ZERO
		land_dip = 0.12
		Sfx.play("step", -2.0, 0.6)
		landed.emit()


func update_health_ui() -> void:
	if health_label:
		health_label.text = "生命值：%d / %d" % [int(health), int(max_health)]


func die() -> void:
	is_dead = true
	velocity = Vector3.ZERO
	Game.lose()
