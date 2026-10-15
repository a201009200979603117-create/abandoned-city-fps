
extends CharacterBody3D

@onready var health_label: Label = get_node("/root/Main/UI/HealthLabel")

@export var max_health: float = 100.0
var health: float = 100.0

# 玩家移動設定
@export var move_speed: float = 5.0
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.002

# 重力
var gravity: float = 9.8

# 攝影機旋轉中心
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D


func _ready() -> void:
	health = max_health
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity)

		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clamp(
			head.rotation.x,
			deg_to_rad(-85.0),
			deg_to_rad(85.0)
		)

	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if event is InputEventMouseButton:
		if event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	# 重力
	if not is_on_floor():
		velocity.y -= gravity * delta

	# 跳躍
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	# 讀取 WASD 移動方向
	var input_dir := Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
        "move_back"
	)

	var direction := (
		transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)
	).normalized()

	if direction:
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, move_speed)
		velocity.z = move_toward(velocity.z, 0.0, move_speed)

	move_and_slide()
func take_damage(damage: float) -> void:
	health -= damage
	health = maxf(health, 0.0)

	print("玩家生命值：", health)
	health_label.text = "生命值：%d / %d" % [int(health), int(max_health)]

	if health <= 0.0:
		die()


func die() -> void:
	print("玩家死亡！")
