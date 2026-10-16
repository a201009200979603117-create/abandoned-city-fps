extends CharacterBody3D

signal damaged(amount: float)

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

	health = maxf(health - damage * (1.0 - armor), 0.0)
	update_health_ui()
	damaged.emit(damage)
	add_shake(clampf(damage / 25.0, 0.3, 1.0))
	Sfx.play("hurt", -2.0)

	if health <= 0.0:
		die()


func update_health_ui() -> void:
	if health_label:
		health_label.text = "生命值：%d / %d" % [int(health), int(max_health)]


func die() -> void:
	is_dead = true
	velocity = Vector3.ZERO
	Game.lose()
