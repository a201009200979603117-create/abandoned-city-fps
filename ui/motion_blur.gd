extends CanvasLayer
# 動態模糊：依相機轉動速度驅動 shaders/motion_blur.gdshader（HUD 之下、3D 之上）

const SHUTTER: float = 0.016      # 等效快門時間（秒）
const MAX_BLUR: float = 0.07      # 單軸最大模糊長度（螢幕比例）

var rect: ColorRect
var mat: ShaderMaterial
var prev_basis: Basis = Basis.IDENTITY
var has_prev: bool = false
var vel: Vector2 = Vector2.ZERO
var radial: float = 0.0


func _ready() -> void:
	layer = 0
	process_mode = Node.PROCESS_MODE_ALWAYS
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/motion_blur.gdshader")
	rect = ColorRect.new()
	rect.material = mat
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.visible = false
	add_child(rect)


func _process(delta: float) -> void:
	var strength := Save.motion_blur if Save.effective_quality() > 0 else 0.0   # 低畫質不啟用動態模糊
	var cam := get_viewport().get_camera_3d()
	if strength <= 0.01 or cam == null or not Game.is_playing() or delta <= 0.0:
		rect.visible = false
		has_prev = false
		vel = Vector2.ZERO
		return
	var cur := cam.global_transform.basis
	var target_vel := Vector2.ZERO
	if has_prev:
		var e := (prev_basis.inverse() * cur).get_euler()
		var vfov := deg_to_rad(cam.fov)
		var aspect := get_viewport().get_visible_rect().size.aspect()
		# 角速度（rad/s）× 快門 → 螢幕比例位移
		var w := Vector2(e.y, e.x) / delta
		target_vel = Vector2(w.x / (vfov * aspect), w.y / vfov) * SHUTTER * strength * 3.0
		# 瞬移/重生時的大幅跳動不模糊
		if absf(e.y) > 0.6 or absf(e.x) > 0.6:
			target_vel = Vector2.ZERO
	prev_basis = cur
	has_prev = true
	vel = vel.lerp(target_vel, minf(delta * 18.0, 1.0))
	vel = vel.clamp(Vector2(-MAX_BLUR, -MAX_BLUR), Vector2(MAX_BLUR, MAX_BLUR))

	var player := get_tree().get_first_node_in_group("player")
	var sprint_target := 0.05 * strength if (player != null and bool(player.get("is_sprinting"))) else 0.0
	radial = lerpf(radial, sprint_target, minf(delta * 5.0, 1.0))

	var active := vel.length() > 0.0008 or radial > 0.002
	rect.visible = active
	if active:
		mat.set_shader_parameter("vel", vel)
		mat.set_shader_parameter("radial", radial)
