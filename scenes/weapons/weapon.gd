
extends Node3D

@export var damage: float = 25.0
@export var fire_rate: float = 0.2
@export var range_distance: float = 100.0
@export var magazine_size: int = 30
@export var reserve_ammo: int = 90

var current_ammo: int = 30
var fire_timer: float = 0.0

@onready var camera: Camera3D = get_viewport().get_camera_3d()
@onready var ammo_label: Label = get_node("/root/Main/UI/AmmoLabel")


func _process(delta: float) -> void:
	fire_timer = maxf(fire_timer - delta, 0.0)

	if Input.is_action_just_pressed("reload"):
		reload_weapon()

	if Input.is_key_pressed(KEY_F) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if fire_timer <= 0.0:
			shoot()
			fire_timer = fire_rate


func shoot() -> void:
	if current_ammo <= 0:
		print("子彈用完了！請按 R 換彈")
		return

	current_ammo -= 1
	update_ammo_ui()
	print("剩餘子彈：", current_ammo)

	if camera == null:
		return

	var space_state := get_world_3d().direct_space_state
	var origin := camera.global_position
	var end := origin - camera.global_transform.basis.z * range_distance

	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.exclude = [get_parent().get_parent().get_parent().get_rid()]

	var result := space_state.intersect_ray(query)

	if result:
		var target = result["collider"]

		if target.has_method("take_damage"):
			target.take_damage(damage)


func reload_weapon() -> void:
	print("按下換彈功能！")

	var needed_ammo: int = magazine_size - current_ammo

	if needed_ammo <= 0 or reserve_ammo <= 0:
		print("目前不需要換彈，或備用子彈已用完")
		return

	var ammo_to_load: int = mini(needed_ammo, reserve_ammo)

	current_ammo += ammo_to_load
	reserve_ammo -= ammo_to_load
	update_ammo_ui()

	print("彈匣：", current_ammo, " / 備用子彈：", reserve_ammo)
func update_ammo_ui() -> void:
	ammo_label.text = "子彈：%d / %d" % [current_ammo, reserve_ammo]
