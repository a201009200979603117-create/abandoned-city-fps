extends CharacterBody3D

signal damaged(amount: float)

@export var max_health: float = 100.0
@export var move_speed: float = 5.0
@export var sprint_multiplier: float = 1.6
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.002

var health: float = 100.0
var is_dead: bool = false
var gravity: float = 9.8
var step_timer: float = 0.0
var bob_time: float = 0.0

@onready var health_label: Label = get_node_or_null("/root/Main/UI/HealthLabel")
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var head_base_y: float = $Head.position.y


func _ready() -> void:
	health = max_health
	update_health_ui()


func _unhandled_input(event: InputEvent) -> void:
	if is_dead or not Game.is_playing():
		return

	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-85.0), deg_to_rad(85.0))


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	var speed := move_speed
	var sprinting := Input.is_action_pressed("sprint") and input_dir.y < 0.0
	if sprinting:
		speed *= sprint_multiplier

	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, move_speed)
		velocity.z = move_toward(velocity.z, 0.0, move_speed)

	move_and_slide()
	_update_head_bob(delta, direction != Vector3.ZERO and is_on_floor(), sprinting)


func _update_head_bob(delta: float, moving: bool, sprinting: bool) -> void:
	if moving:
		var rate := 13.0 if sprinting else 9.0
		bob_time += delta * rate
		head.position.y = head_base_y + sin(bob_time) * 0.04
		step_timer -= delta
		if step_timer <= 0.0:
			Sfx.play("step", -12.0, randf_range(0.85, 1.1))
			step_timer = 0.3 if sprinting else 0.42
	else:
		head.position.y = lerpf(head.position.y, head_base_y, delta * 10.0)
		step_timer = 0.0


func take_damage(damage: float) -> void:
	if is_dead:
		return

	health = maxf(health - damage, 0.0)
	update_health_ui()
	damaged.emit(damage)
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
