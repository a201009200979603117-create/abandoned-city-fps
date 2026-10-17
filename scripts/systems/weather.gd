extends Node3D
# 天氣與時段：套用在關卡原本的主題色之上。
#   時段：黃昏（維持原樣）/ 夜晚（變暗 + 玩家頭燈）/ 黎明（暖色調）
#   天氣：晴 / 下雨 / 暴風雨（閃電雷聲）/ 濃霧 / 落塵（飄浮火星）
# 雨滴與火星跟隨玩家，數量依畫質分級。

const TOD_NAMES: Dictionary = {"dusk": "黃昏", "night": "夜晚", "dawn": "黎明"}
const WEATHER_NAMES: Dictionary = {"clear": "晴", "rain": "下雨", "storm": "暴風雨", "fog": "濃霧", "ash": "落塵"}
const TOD_BY_LEVEL: Array = ["dusk", "night", "dusk", "dawn", "dusk", "night", "dawn", "night", "night", "night"]
const WEATHER_BY_LEVEL: Array = ["clear", "rain", "clear", "fog", "clear", "rain", "ash", "ash", "storm", "storm"]

var env: Environment
var sun: DirectionalLight3D
var kind: String = "clear"
var tod: String = "dusk"
var quality: int = 2
var player: Node3D = null
var rain: CPUParticles3D = null
var embers: CPUParticles3D = null
var lightning_t: float = 8.0


static func tod_for_level(n: int) -> String:
	return TOD_BY_LEVEL[clampi(n, 1, TOD_BY_LEVEL.size()) - 1]


static func weather_for_level(n: int) -> String:
	return WEATHER_BY_LEVEL[clampi(n, 1, WEATHER_BY_LEVEL.size()) - 1]


static func label(tod_id: String, weather_id: String) -> String:
	return "%s・%s" % [TOD_NAMES.get(tod_id, ""), WEATHER_NAMES.get(weather_id, "")]


static func label_for_level(n: int) -> String:
	return label(tod_for_level(n), weather_for_level(n))


func setup(env_: Environment, sun_: DirectionalLight3D, kind_: String, tod_: String, quality_: int) -> void:
	env = env_
	sun = sun_
	kind = kind_
	tod = tod_
	quality = quality_
	_apply_time()
	_apply_weather()
	if tod == "night":
		_add_headlamp()


func _sky() -> ProceduralSkyMaterial:
	if env != null and env.sky != null and env.sky.sky_material is ProceduralSkyMaterial:
		return env.sky.sky_material as ProceduralSkyMaterial
	return null


func _apply_time() -> void:
	if env == null:
		return
	var sky := _sky()
	match tod:
		"night":
			# 原本就很暗的主題（午夜街道、末日終局）只做輕微調整，避免黑到看不見
			var already_dark := env.ambient_light_color.get_luminance() < 0.2
			env.ambient_light_energy *= 0.95 if already_dark else 0.62
			env.fog_light_color = env.fog_light_color.darkened(0.35).lerp(Color(0.12, 0.16, 0.26), 0.25)
			env.adjustment_brightness = 0.95
			if sun != null:
				sun.light_energy *= 0.8 if already_dark else 0.35
				sun.light_color = sun.light_color.lerp(Color(0.5, 0.6, 0.95), 0.6)
			if sky != null and not already_dark:
				sky.sky_top_color = sky.sky_top_color.darkened(0.4)
				sky.sky_horizon_color = sky.sky_horizon_color.darkened(0.35).lerp(Color(0.1, 0.14, 0.25), 0.25)
				sky.ground_horizon_color = sky.sky_horizon_color.darkened(0.3)
		"dawn":
			env.ambient_light_energy *= 1.05
			env.fog_light_color = env.fog_light_color.lerp(Color(0.85, 0.6, 0.5), 0.3)
			if sun != null:
				sun.light_color = sun.light_color.lerp(Color(1.0, 0.72, 0.55), 0.5)
			if sky != null:
				sky.sky_horizon_color = sky.sky_horizon_color.lerp(Color(1.0, 0.62, 0.45), 0.45)
				sky.ground_horizon_color = sky.sky_horizon_color.darkened(0.3)


func _apply_weather() -> void:
	if env == null:
		return
	var rain_amount := 0
	match kind:
		"rain":
			env.fog_density *= 1.3
			env.ambient_light_energy *= 0.85
			if sun != null:
				sun.light_energy *= 0.7
			rain_amount = [90, 220, 420][quality]
			Sfx.start_rain(0.55)
		"storm":
			env.fog_density *= 1.5
			env.ambient_light_energy *= 0.78
			if sun != null:
				sun.light_energy *= 0.55
			rain_amount = [130, 320, 620][quality]
			Sfx.start_rain(1.0)
		"fog":
			env.fog_density = minf(env.fog_density * 2.0, 0.085)
			env.fog_light_color = env.fog_light_color.lerp(Color(0.72, 0.74, 0.76), 0.25)
			if sun != null:
				sun.light_energy *= 0.6
			Sfx.stop_rain()
		"ash":
			Sfx.stop_rain()
			_make_embers()
		_:
			Sfx.stop_rain()
	if rain_amount > 0:
		_make_rain(rain_amount)


func _make_rain(amount: int) -> void:
	rain = CPUParticles3D.new()
	rain.amount = amount
	rain.lifetime = 0.5
	rain.preprocess = 0.5
	rain.local_coords = false
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(20.0, 0.3, 20.0)
	rain.direction = Vector3(0.12, -1.0, 0.05)
	rain.spread = 2.0
	rain.initial_velocity_min = 22.0
	rain.initial_velocity_max = 28.0
	rain.gravity = Vector3.ZERO
	var bm := BoxMesh.new()
	bm.size = Vector3(0.012, 0.55, 0.012)
	rain.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.72, 0.8, 0.92, 0.32)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rain.material_override = m
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rain)


func _make_embers() -> void:
	embers = CPUParticles3D.new()
	embers.amount = [20, 45, 80][quality]
	embers.lifetime = 4.0
	embers.preprocess = 3.0
	embers.local_coords = false
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	embers.emission_box_extents = Vector3(18.0, 1.5, 18.0)
	embers.direction = Vector3(0.3, 1.0, 0.2)
	embers.spread = 25.0
	embers.initial_velocity_min = 0.8
	embers.initial_velocity_max = 2.2
	embers.gravity = Vector3.ZERO
	var sm := SphereMesh.new()
	sm.radius = 0.035
	sm.height = 0.07
	sm.radial_segments = 4
	sm.rings = 2
	embers.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.55, 0.15)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	embers.material_override = m
	embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(embers)


# 夜晚：玩家頭燈（跟著鏡頭）
func _add_headlamp() -> void:
	var cam := get_parent().get_parent().get_node_or_null("Player/Head/Camera3D") as Camera3D
	if cam == null:
		return
	var lamp := SpotLight3D.new()
	lamp.light_color = Color(1.0, 0.95, 0.85)
	lamp.light_energy = 4.0 if quality >= 1 else 3.0
	lamp.spot_range = 34.0 if quality >= 1 else 22.0
	lamp.spot_angle = 38.0
	lamp.spot_attenuation = 0.6
	lamp.shadow_enabled = false
	cam.add_child(lamp)


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node3D
	if player != null:
		global_position = player.global_position + Vector3(0.0, 11.0, 0.0)
	if kind == "storm" and Game.is_playing() and env != null:
		lightning_t -= delta
		if lightning_t <= 0.0:
			lightning_t = randf_range(7.0, 16.0)
			_flash()


# 閃電：環境光與日光瞬間提亮（雙閃），雷聲依距離延遲
func _flash() -> void:
	var base_amb := env.ambient_light_energy
	var base_sun := sun.light_energy if sun != null else 0.0
	var tw := create_tween()
	tw.tween_property(env, "ambient_light_energy", base_amb + 3.0, 0.04)
	tw.tween_property(env, "ambient_light_energy", base_amb + 0.4, 0.07)
	tw.tween_property(env, "ambient_light_energy", base_amb + 3.5, 0.04)
	tw.tween_property(env, "ambient_light_energy", base_amb, 0.35)
	if sun != null:
		var ts := create_tween()
		ts.tween_property(sun, "light_energy", base_sun + 1.5, 0.04)
		ts.tween_property(sun, "light_energy", base_sun, 0.45)
	Sfx.thunder(randf_range(0.3, 2.2))
