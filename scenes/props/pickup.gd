
extends Area3D

enum PickupType {
	AMMO,
	HEALTH
}

@export var pickup_type: PickupType = PickupType.AMMO
@export var ammo_amount: int = 30
@export var health_amount: float = 25.0

var float_time: float = 0.0
var start_y: float = 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	start_y = global_position.y
	update_pickup_color()


func update_pickup_color() -> void:
	var material := StandardMaterial3D.new()

	if pickup_type == PickupType.AMMO:
		material.albedo_color = Color("#FFD54F")
	else:
		material.albedo_color = Color("#FF4444")

	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var mesh_instance := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh_instance:
		mesh_instance.material_override = material

var player_in_range: Node3D = null
var lifetime: float = 45.0
@onready var pickup_hint: Label = get_node("/root/Main/UI/PickupHint")

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_in_range = body

		if pickup_type == PickupType.AMMO:
			pickup_hint.text = "按 E 拾取彈藥"
		else:
			pickup_hint.text = "按 E 拾取醫療補給"

		pickup_hint.visible = true

func _on_body_exited(body: Node3D) -> void:
	if body == player_in_range:
		player_in_range = null
		pickup_hint.visible = false

func _process(delta: float) -> void:
	float_time += delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return
	rotate_y(3.5 * delta)
	global_position.y = maxf(start_y, 0.8) + sin(float_time * 3.0) * 0.3

	if player_in_range != null and Input.is_action_just_pressed("interact"):
		collect_pickup()


func _exit_tree() -> void:
	if player_in_range != null and pickup_hint != null:
		pickup_hint.visible = false


func collect_pickup() -> void:
	if not is_instance_valid(player_in_range):
		return

	var body = player_in_range
	pickup_hint.visible = false
	Sfx.play("pickup")

	if pickup_type == PickupType.AMMO:
		var weapon = body.get_node_or_null("Head/Camera3D/Weapon")

		if weapon == null:
			return

		weapon.add_reserve(ammo_amount)
		print("拾取彈藥！備用子彈：", weapon.reserve_ammo)

	elif pickup_type == PickupType.HEALTH:
		if not "health" in body or not "max_health" in body:
			return

		body.health = minf(body.health + health_amount, body.max_health)

		var health_label = body.get_node_or_null("/root/Main/UI/HealthLabel")
		if health_label:
			health_label.text = "生命值：%d / %d" % [
				int(body.health),
				int(body.max_health)
			]

		print("拾取醫療補給！生命值：", body.health)

	queue_free()
