extends Node3D
# 以程式生成城市：棋盤式街區、多樣化建築、車輛殘骸、路障、路燈與邊界牆
# 地圖範圍為 ±HALF（200×200）；路燈使用少量動態光源池，只照亮玩家附近

const HALF: float = 100.0
const ROAD_AXES: Array[float] = [-50.0, 0.0, 50.0]
const ROAD_WIDTH: float = 12.0
const LIGHT_POOL_SIZE: int = 4
const LIGHT_ENERGY: float = 1.6
const GROUND_SHADER: Shader = preload("res://shaders/ground.gdshader")
const BUILDING_SHADER: Shader = preload("res://shaders/building.gdshader")
const GROUND_LITE: Shader = preload("res://shaders/ground_lite.gdshader")
const BUILDING_LITE: Shader = preload("res://shaders/building_lite.gdshader")
const LevelDB = preload("res://scripts/data/level_db.gd")

var rng := RandomNumberGenerator.new()
var material_cache: Dictionary = {}
var building_material: ShaderMaterial
var footprints: Array[Rect2] = []
var lamp_positions: Array[Vector3] = []
var pool: Array[OmniLight3D] = []
var pool_lamp: Array[int] = []
var fires: Array[OmniLight3D] = []
var player: Node3D
var flicker_timer: float = 0.0
var assign_timer: float = 0.0


const BARREL_SCRIPT = preload("res://scripts/systems/explosive_barrel.gd")
const WEATHER_SCRIPT = preload("res://scripts/systems/weather.gd")
const TOXIC_SCRIPT = preload("res://scripts/systems/toxic_zone.gd")

var theme: Dictionary = {}
var quality_level: int = 2
var cam_far_override: float = 0.0
var weather_text: String = ""
var perf_t: float = 0.0
var perf_sum: float = 0.0
var perf_n: int = 0
var perf_done: bool = false
var low_spec: bool = false   # 網頁/手機：關閉陰影與泛光、減少粒子與動態光源
var unit_box: BoxMesh        # 小型道具共用的 1×1×1 方塊（以縮放取得尺寸）
var skip_chance: float = 0.28


var last_yield_ms: int = 0


func _ready() -> void:
	# 渲染解析度：低畫質在遊戲中以 1152×648 內部解析度繪製再放大（網頁 / 低階 GPU 的填充率是最大瓶頸）；選單維持清晰
	var win := get_tree().root
	if Game.gameplay_boot and Save.effective_quality() == 0:
		win.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	else:
		win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	# 主選單啟動時不需要城市場景（開始遊戲會重新載入場景）：跳過建構，省下約 2000 個節點與數百 MB 顯存
	if not Game.gameplay_boot:
		return
	if Game.is_br():
		theme = LevelDB.BR_THEME
		rng.seed = LevelDB.BR_SEED
		skip_chance = LevelDB.BR_SKIP
	else:
		theme = Game.level_cfg["theme"]
		rng.seed = int(Game.level_cfg["seed"])
		skip_chance = float(Game.level_cfg["skip"])
	quality_level = Save.effective_quality()
	# 低畫質一律精簡；中畫質在手機/網頁精簡；高畫質才有陰影與泛光
	low_spec = quality_level == 0 or (quality_level == 1 and (Save.touch_mode or OS.has_feature("web")))
	unit_box = BoxMesh.new()
	unit_box.size = Vector3.ONE
	building_material = ShaderMaterial.new()
	# 低畫質（含手機 / 網頁預設）改用輕量著色器：像素著色器是這類裝置最大的 GPU 負擔
	building_material.shader = BUILDING_LITE if low_spec else BUILDING_SHADER
	_setup_environment()
	_setup_ground()
	_build_roads()
	_load_async()   # 其餘建構分幀進行（不 await：讓載入畫面能持續更新）


# 分幀建構：每幀最多做約 12 毫秒的工作，網頁 / 手機上畫面不會凍結，並顯示載入進度
func _yield_slice(progress: float = -1.0) -> void:
	if progress >= 0.0:
		Game.load_progress = progress
	if Time.get_ticks_msec() - last_yield_ms > 12:
		await get_tree().process_frame
		last_yield_ms = Time.get_ticks_msec()


func _load_async() -> void:
	last_yield_ms = Time.get_ticks_msec()
	await get_tree().process_frame
	await _build_buildings()
	Game.load_progress = 0.65
	await _build_props()
	Game.load_progress = 0.82
	await _yield_slice()
	_build_drums()
	_build_hazards()
	await _yield_slice(0.88)
	_build_street_lights()
	_build_boundary()
	await _yield_slice(0.95)
	player = get_tree().get_first_node_in_group("player") as Node3D
	_assign_lights()
	Sfx.start_ambient()
	# 多等兩幀：著色器與管線在載入畫面後面先編譯，進入遊戲時不會再卡一下
	await get_tree().process_frame
	await get_tree().process_frame
	Game.load_progress = 1.0
	Game.level_ready = true
	Game.level_loaded.emit()


func _process(delta: float) -> void:
	_perf_guard(delta)
	assign_timer -= delta
	if assign_timer <= 0.0:
		assign_timer = 0.3
		_assign_lights()
	flicker_timer -= delta
	if flicker_timer > 0.0:
		return
	flicker_timer = 0.06
	for f in fires:
		f.light_energy = randf_range(0.9, 1.9)
	for i in pool.size():
		if i % 3 == 0:
			pool[i].light_energy = LIGHT_ENERGY * (0.05 if randf() < 0.14 else randf_range(0.7, 1.0))


# 自適應畫質：開局前 8 秒若平均 FPS 過低，自動降一級畫質（只在手機/網頁；一次性）
func _perf_guard(delta: float) -> void:
	if perf_done or not Game.is_playing():
		return
	perf_t += delta
	if perf_t < 2.0:
		return   # 略過載入時的卡頓
	perf_sum += Engine.get_frames_per_second() * delta
	perf_n += 1
	if perf_t < 8.0:
		return
	perf_done = true
	if not (Save.touch_mode or OS.has_feature("web")) or quality_level <= 0:
		return
	var avg := perf_sum / maxf(perf_t - 2.0, 0.1)
	if avg < 32.0:
		quality_level -= 1
		Save.quality = quality_level
		Save.save()
		low_spec = true
		get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		get_viewport().scaling_3d_scale = [0.65, 0.8, 1.0][quality_level]
		var sun := get_parent().get_node_or_null("World/DirectionalLight3D") as DirectionalLight3D
		if sun != null:
			sun.shadow_enabled = false
		Game.banner.emit("流暢度不足，已自動降低畫質（可在設定調整）")


func _setup_environment() -> void:
	var we := get_parent().get_node_or_null("World/WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null:
		var env := we.environment
		env.fog_enabled = true
		env.fog_light_color = theme["fog"]
		env.fog_density = theme["fog_density"]
		env.fog_sky_affect = 0.8
		env.fog_height = 0.0
		env.fog_height_density = 0.05
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.tonemap_exposure = 1.05
		env.glow_enabled = not low_spec
		env.glow_intensity = 0.6
		env.glow_bloom = 0.05
		env.adjustment_enabled = true
		env.adjustment_saturation = 0.72
		env.adjustment_contrast = 1.12
		env.adjustment_brightness = 0.98
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = theme["ambient"]
		env.ambient_light_energy = theme["ambient_energy"]
		if env.sky != null and env.sky.sky_material is ProceduralSkyMaterial:
			var sky_mat := env.sky.sky_material as ProceduralSkyMaterial
			sky_mat.sky_top_color = theme["sky_top"]
			sky_mat.sky_horizon_color = theme["sky_horizon"]
			sky_mat.ground_horizon_color = (theme["sky_horizon"] as Color).darkened(0.3)
			sky_mat.ground_bottom_color = (theme["sky_top"] as Color).darkened(0.2)
	var sun := get_parent().get_node_or_null("World/DirectionalLight3D") as DirectionalLight3D
	if sun != null:
		sun.light_energy = theme["sun_energy"]
		sun.light_color = theme["sun"]
		sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
		sun.directional_shadow_max_distance = 70.0
		if low_spec:
			sun.shadow_enabled = false   # 手機/網頁效能考量
	var cam := get_parent().get_node_or_null("Player/Head/Camera3D") as Camera3D
	if cam != null:
		cam.far = cam_far_override if cam_far_override > 0.0 else 130.0   # 濃霧之外不需要繪製，縮短遠裁切面
	# 畫質對應的 3D 繪製解析度（低於 1.0 時以雙線性放大，降低填充率負擔）
	var res_scale: float = [1.0, 0.8, 1.0][quality_level]   # 低畫質已改用視窗縮放（見 _ready），避免重複縮小
	if res_scale < 1.0:
		get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		get_viewport().scaling_3d_scale = res_scale
	if quality_level == 0:
		cam_far_override = 85.0
	_setup_weather()
	_setup_ash()


# 天氣與時段：殭屍關卡依關卡編號固定；大逃殺每場隨機
func _setup_weather() -> void:
	var we := get_parent().get_node_or_null("World/WorldEnvironment") as WorldEnvironment
	var sun := get_parent().get_node_or_null("World/DirectionalLight3D") as DirectionalLight3D
	if we == null or we.environment == null:
		return
	var kind: String
	var tod: String
	if Game.is_br():
		kind = ["clear", "clear", "rain", "fog", "storm"].pick_random()
		tod = ["dusk", "night", "dawn"].pick_random()
	else:
		kind = WEATHER_SCRIPT.weather_for_level(Game.level)
		tod = WEATHER_SCRIPT.tod_for_level(Game.level)
	var w := Node3D.new()
	w.set_script(WEATHER_SCRIPT)
	add_child(w)
	w.call("setup", we.environment, sun, kind, tod, quality_level)
	weather_text = WEATHER_SCRIPT.label(tod, kind)


func _setup_ash() -> void:
	# 飄落的灰燼與塵埃，跟著玩家移動
	var host := get_parent().get_node_or_null("Player") as Node3D
	if host == null:
		return
	var ash := CPUParticles3D.new()
	ash.amount = 40 if low_spec else 110
	ash.lifetime = 8.0
	ash.preprocess = 4.0
	ash.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	ash.emission_box_extents = Vector3(22.0, 6.0, 22.0)
	ash.position = Vector3(0.0, 6.0, 0.0)
	ash.direction = Vector3(0.4, -1.0, 0.2)
	ash.spread = 25.0
	ash.initial_velocity_min = 0.25
	ash.initial_velocity_max = 0.9
	ash.gravity = Vector3(0.25, -0.15, 0.1)
	ash.local_coords = false
	var flake := QuadMesh.new()
	flake.size = Vector2(0.045, 0.045)
	ash.mesh = flake
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = (theme["fog"] as Color).lightened(0.35)
	m.albedo_color.a = 0.55
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ash.material_override = m
	ash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(ash)


func _ground_material(color: Color, asphalt: float) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = GROUND_LITE if low_spec else GROUND_SHADER
	sm.set_shader_parameter("base_color", color)
	sm.set_shader_parameter("asphalt", asphalt)
	return sm


func _make_material(color: Color) -> StandardMaterial3D:
	# 相同顏色共用同一個材質（燈頭等需自訂的材質請另行建立）
	if material_cache.has(color):
		return material_cache[color]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.95
	material_cache[color] = m
	return m


func _setup_ground() -> void:
	var ground := get_parent().get_node_or_null("World/Ground/MeshInstance3D") as MeshInstance3D
	if ground != null:
		(ground.mesh as PlaneMesh).size = Vector2(HALF * 2.0, HALF * 2.0)
		ground.material_override = _ground_material(theme["ground"], 0.0)
	var ground_col := get_parent().get_node_or_null("World/Ground/CollisionShape3D") as CollisionShape3D
	if ground_col != null:
		(ground_col.shape as BoxShape3D).size = Vector3(HALF * 2.0, 0.2, HALF * 2.0)


func _build_roads() -> void:
	var road_mat := _ground_material(Color(0.1, 0.1, 0.105), 1.0)
	var line_mat := _make_material(Color(0.4, 0.37, 0.22))

	# 路面：貼地薄方塊（碰撞由地面負責）
	for axis in ROAD_AXES:
		_add_visual_box(Vector3(axis, 0.02, 0.0), Vector3(ROAD_WIDTH, 0.04, HALF * 2.0), road_mat)
		_add_visual_box(Vector3(0.0, 0.025, axis), Vector3(HALF * 2.0, 0.04, ROAD_WIDTH), road_mat)

	# 中線虛線：MultiMesh 一次繪製，交叉口內不畫
	var dashes: Array[Transform3D] = []
	var t := -HALF + 3.0
	while t < HALF:
		if not _in_intersection(t):
			for axis in ROAD_AXES:
				dashes.append(Transform3D(Basis.IDENTITY, Vector3(axis, 0.05, t)))
				dashes.append(Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(t, 0.055, axis)))
		t += 6.0
	var dash_mesh := BoxMesh.new()
	dash_mesh.size = Vector3(0.2, 0.02, 2.2)
	_add_multimesh(dash_mesh, line_mat, dashes)


func _in_intersection(t: float) -> bool:
	for other in ROAD_AXES:
		if absf(t - other) < ROAD_WIDTH * 0.5 + 1.0:
			return true
	return false


func _add_visual_box(pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _add_multimesh(mesh: Mesh, mat: Material, xforms: Array[Transform3D]) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _block_ranges() -> Array[Vector2]:
	# 道路之間（含外圍）的可建地範圍，單軸
	var edges: Array[float] = [-HALF]
	for a in ROAD_AXES:
		edges.append(a - ROAD_WIDTH * 0.5)
		edges.append(a + ROAD_WIDTH * 0.5)
	edges.append(HALF)
	var out: Array[Vector2] = []
	for i in range(0, edges.size(), 2):
		out.append(Vector2(edges[i] + 2.0, edges[i + 1] - 2.0))
	return out


func _build_buildings() -> void:
	var ranges := _block_ranges()
	var total := float(maxi(ranges.size() * ranges.size(), 1))
	var n := 0
	for rx in ranges:
		for rz in ranges:
			_fill_block(rx, rz)
			n += 1
			await _yield_slice(0.05 + 0.6 * float(n) / total)


func _fill_block(rx: Vector2, rz: Vector2) -> void:
	# 每個街區切成 3×3 地塊，隨機略過部分地塊形成中庭與空地
	var cols := 3
	var cw := (rx.y - rx.x) / cols
	var ch := (rz.y - rz.x) / cols
	for i in cols:
		for j in cols:
			if rng.randf() < skip_chance:
				continue
			var w := rng.randf_range(cw * 0.55, cw * 0.92)
			var d := rng.randf_range(ch * 0.55, ch * 0.92)
			var cx := rx.x + cw * (i + 0.5) + rng.randf_range(-1.0, 1.0)
			var cz := rz.x + ch * (j + 0.5) + rng.randf_range(-1.0, 1.0)
			var tall := rng.randf() < 0.22
			var h := rng.randf_range(20.0, 34.0) if tall else rng.randf_range(7.0, 18.0)
			# 部分建築半毀：樓層被削短，頂端露出鋼筋與斷牆
			var ruined := rng.randf() < 0.35
			if ruined:
				h *= rng.randf_range(0.45, 0.8)
			_place_building(Vector3(cx, h * 0.5, cz), Vector3(w, h, d))
			footprints.append(Rect2(cx - w * 0.5, cz - d * 0.5, w, d))
			if ruined:
				_add_broken_top(Vector3(cx, h, cz), w, d)
			if rng.randf() < 0.55:
				_add_rubble(Vector3(cx, 0.0, cz), w, d)


func _place_building(pos: Vector3, size: Vector3) -> void:
	var body := _add_box(pos, size, building_material)
	var mi := body.get_child(0) as MeshInstance3D
	var g := rng.randf_range(0.26, 0.40)
	mi.set_instance_shader_parameter("tint", Vector3(g + rng.randf_range(0.0, 0.05), g, g - rng.randf_range(0.0, 0.04)))
	mi.set_instance_shader_parameter("seed", rng.randf_range(0.0, 100.0))


func _add_broken_top(top: Vector3, w: float, d: float) -> void:
	# 殘存的牆片與歪斜的鋼筋
	var concrete := _make_material(Color(0.2, 0.2, 0.19))
	var rebar := _make_material(Color(0.22, 0.1, 0.06))
	for k in rng.randi_range(2, 4):
		var sw := rng.randf_range(0.8, w * 0.35)
		var sh := rng.randf_range(0.8, 2.6)
		var px := top.x + rng.randf_range(-w * 0.4, w * 0.4)
		var pz := top.z + rng.randf_range(-d * 0.4, d * 0.4)
		_add_box(Vector3(px, top.y + sh * 0.5, pz), Vector3(sw, sh, rng.randf_range(0.3, 0.6)), concrete, rng.randf_range(0.0, PI))
	for k in rng.randi_range(3, 6):
		var rh := rng.randf_range(1.5, 3.5)
		var bar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.06, rh, 0.06)
		bar.mesh = bm
		bar.material_override = rebar
		bar.position = Vector3(top.x + rng.randf_range(-w * 0.45, w * 0.45), top.y + rh * 0.5, top.z + rng.randf_range(-d * 0.45, d * 0.45))
		bar.rotation = Vector3(rng.randf_range(-0.4, 0.4), 0.0, rng.randf_range(-0.4, 0.4))
		bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(bar)


func _add_rubble(center: Vector3, w: float, d: float) -> void:
	# 牆根的碎塊堆（有碰撞，可當掩體）
	var mats: Array[StandardMaterial3D] = [
		_make_material(Color(0.24, 0.23, 0.21)),
		_make_material(Color(0.19, 0.18, 0.17)),
		_make_material(Color(0.3, 0.14, 0.1)),
	]
	for k in rng.randi_range(2, 4):
		var side := rng.randi() % 4
		var off_x := rng.randf_range(-w * 0.5, w * 0.5)
		var off_z := rng.randf_range(-d * 0.5, d * 0.5)
		match side:
			0: off_z = d * 0.5 + rng.randf_range(0.3, 1.4)
			1: off_z = -d * 0.5 - rng.randf_range(0.3, 1.4)
			2: off_x = w * 0.5 + rng.randf_range(0.3, 1.4)
			_: off_x = -w * 0.5 - rng.randf_range(0.3, 1.4)
		var x := center.x + off_x
		var z := center.z + off_z
		if _on_road(x, z, 0.5) or _near_spawn(x, z):
			continue
		var sz := Vector3(rng.randf_range(0.4, 1.6), rng.randf_range(0.25, 0.9), rng.randf_range(0.4, 1.6))
		var b := _add_box(Vector3(x, sz.y * 0.5 - 0.05, z), sz, mats[rng.randi() % mats.size()], rng.randf_range(0.0, PI))
		b.rotation.x = rng.randf_range(-0.25, 0.25)
		b.rotation.z = rng.randf_range(-0.25, 0.25)


func _add_box(pos: Vector3, size: Vector3, mat: Material, yaw: float = 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = yaw
	var mesh_instance := MeshInstance3D.new()
	if mat == building_material:
		var box := BoxMesh.new()
		box.size = size
		mesh_instance.mesh = box
	else:
		# 小型道具：共用單一網格，以縮放取得尺寸，並在遠處自動隱藏
		mesh_instance.mesh = unit_box
		mesh_instance.scale = size
		mesh_instance.visibility_range_end = 85.0
		mesh_instance.visibility_range_end_margin = 10.0
		mesh_instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	mesh_instance.material_override = mat
	body.add_child(mesh_instance)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	add_child(body)
	return body


func _near_spawn(x: float, z: float) -> bool:
	return Vector2(x, z).length() < 7.0


func _in_footprint(x: float, z: float, margin: float) -> bool:
	for r in footprints:
		if r.grow(margin).has_point(Vector2(x, z)):
			return true
	return false


func _on_road(x: float, z: float, margin: float) -> bool:
	var half := ROAD_WIDTH * 0.5 + margin
	for a in ROAD_AXES:
		if absf(x - a) < half or absf(z - a) < half:
			return true
	return false


func _build_props() -> void:
	# 車輛殘骸（沿道路）
	for i in 36:
		if i % 6 == 0:
			await _yield_slice()
		var axis: float = ROAD_AXES[rng.randi() % ROAD_AXES.size()]
		var along := rng.randf_range(-HALF + 4.0, HALF - 4.0)
		var across := axis + rng.randf_range(-3.5, 3.5)
		var along_z := rng.randf() < 0.5
		var pos := Vector3(across, 0.55, along) if along_z else Vector3(along, 0.55, across)
		if _near_spawn(pos.x, pos.z):
			continue
		var yaw := rng.randf_range(-0.35, 0.35) + (PI if rng.randf() < 0.5 else 0.0)
		if not along_z:
			yaw += PI / 2.0
		var tint := rng.randf_range(0.0, 1.0)
		var burnt := rng.randf() < 0.45
		var body_col := Color(0.07, 0.065, 0.06) if burnt else Color(0.26 + tint * 0.1, 0.18 + tint * 0.05, 0.13).darkened(0.25)
		var car := _add_box(pos, Vector3(1.8, 0.7, 4.2), _make_material(body_col), yaw)
		if rng.randf() < 0.18:
			car.rotation.z = PI * 0.5 * (1.0 if rng.randf() < 0.5 else -1.0)   # 翻覆
			car.position.y = 0.9
		elif rng.randf() < 0.3:
			car.rotation.x = rng.randf_range(-0.12, 0.12)
		var cabin := MeshInstance3D.new()
		var cabin_mesh := BoxMesh.new()
		cabin_mesh.size = Vector3(1.6, 0.6, 2.0)
		cabin.mesh = cabin_mesh
		cabin.material_override = _make_material(Color(0.03, 0.03, 0.035) if burnt else Color(0.08, 0.09, 0.09))
		cabin.position = Vector3(0.0, 0.65, 0.2)
		car.add_child(cabin)
		var cabin_shape := CollisionShape3D.new()
		var cabin_box := BoxShape3D.new()
		cabin_box.size = cabin_mesh.size
		cabin_shape.shape = cabin_box
		cabin_shape.position = cabin.position
		car.add_child(cabin_shape)

	# 水泥路障
	for i in 40:
		if i % 8 == 0:
			await _yield_slice()
		var axis: float = ROAD_AXES[rng.randi() % ROAD_AXES.size()]
		var along := rng.randf_range(-HALF + 4.0, HALF - 4.0)
		var across := axis + rng.randf_range(-5.0, 5.0)
		var pos := Vector3(across, 0.45, along) if rng.randf() < 0.5 else Vector3(along, 0.45, across)
		if _near_spawn(pos.x, pos.z):
			continue
		_add_box(pos, Vector3(2.4, 0.9, 0.5), _make_material(Color(0.27, 0.27, 0.25)), rng.randf_range(-0.8, 0.8))

	# 木箱、垃圾箱與瓦礫（街區空地與建築旁）
	var placed := 0
	var tries := 0
	while placed < 90 and tries < 800:
		tries += 1
		if tries % 16 == 0:
			await _yield_slice()
		var x := rng.randf_range(-HALF + 3.0, HALF - 3.0)
		var z := rng.randf_range(-HALF + 3.0, HALF - 3.0)
		if _in_footprint(x, z, 1.5) or _on_road(x, z, 1.0):
			continue
		placed += 1
		var kind := rng.randf()
		if kind < 0.4:
			var s := rng.randf_range(0.9, 1.4)
			_add_box(Vector3(x, s * 0.5, z), Vector3(s, s, s), _make_material(Color(0.22, 0.16, 0.1)), rng.randf_range(0.0, PI))
		elif kind < 0.6:
			_add_box(Vector3(x, 0.6, z), Vector3(1.8, 1.2, 1.0), _make_material(Color(0.14, 0.17, 0.13)), rng.randf_range(-0.3, 0.3))
		else:
			_add_box(Vector3(x, 0.2, z), Vector3(rng.randf_range(1.0, 2.2), 0.4, rng.randf_range(1.0, 2.2)), _make_material(Color(0.21, 0.2, 0.19)), rng.randf_range(0.0, PI))


func _build_hazards() -> void:
	# 殭屍關卡：毒氣區（玩家與殭屍都會受傷）
	if Game.is_br():
		return
	var count := 2 + Game.level / 3
	var placed := 0
	var tries := 0
	while placed < count and tries < 300:
		tries += 1
		var x := rng.randf_range(-HALF + 12.0, HALF - 12.0)
		var z := rng.randf_range(-HALF + 12.0, HALF - 12.0)
		if _in_footprint(x, z, 6.5) or _near_spawn(x, z) or Vector2(x, z).length() < 20.0:
			continue
		placed += 1
		var zone := Node3D.new()
		zone.set_script(TOXIC_SCRIPT)
		zone.position = Vector3(x, 0.0, z)
		add_child(zone)


func _build_drums() -> void:
	# 生鏽油桶，少數仍在燃燒（提供火光）
	var rust := _make_material(Color(0.3, 0.13, 0.07))
	var placed := 0
	var tries := 0
	while placed < 34 and tries < 400:
		tries += 1
		var x := rng.randf_range(-HALF + 4.0, HALF - 4.0)
		var z := rng.randf_range(-HALF + 4.0, HALF - 4.0)
		if _in_footprint(x, z, 1.0) or _near_spawn(x, z):
			continue
		placed += 1
		if placed % 4 == 0:
			# 紅色爆炸油桶（可射擊引爆）
			var barrel := StaticBody3D.new()
			barrel.set_script(BARREL_SCRIPT)
			barrel.position = Vector3(x, 0.45, z)
			add_child(barrel)
			continue
		var body := StaticBody3D.new()
		body.position = Vector3(x, 0.45, z)
		var mi := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.3
		cyl.bottom_radius = 0.3
		cyl.height = 0.9
		cyl.radial_segments = 10
		mi.mesh = cyl
		mi.material_override = rust
		body.add_child(mi)
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = 0.3
		shape.height = 0.9
		cs.shape = shape
		body.add_child(cs)
		add_child(body)
		if placed % 6 == 0:
			var fire := OmniLight3D.new()
			fire.light_color = Color(1.0, 0.55, 0.2)
			fire.light_energy = 1.4
			fire.omni_range = 9.0
			fire.distance_fade_enabled = true
			fire.distance_fade_begin = 28.0
			fire.distance_fade_length = 8.0
			fire.position = Vector3(0.0, 1.0, 0.0)
			body.add_child(fire)
			fires.append(fire)
			var flames := CPUParticles3D.new()
			flames.amount = 6 if low_spec else 10
			flames.lifetime = 0.9
			flames.direction = Vector3.UP
			flames.spread = 12.0
			flames.initial_velocity_min = 0.6
			flames.initial_velocity_max = 1.4
			flames.gravity = Vector3(0.0, 0.8, 0.0)
			flames.scale_amount_min = 0.5
			flames.scale_amount_max = 1.0
			var fq := SphereMesh.new()
			fq.radius = 0.12
			fq.height = 0.24
			fq.radial_segments = 6
			fq.rings = 3
			flames.mesh = fq
			var fmat := StandardMaterial3D.new()
			fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			fmat.albedo_color = Color(1.0, 0.45, 0.1, 0.8)
			fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			flames.material_override = fmat
			flames.position = Vector3(0.0, 0.55, 0.0)
			flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			body.add_child(flames)


func _build_street_lights() -> void:
	# 路燈沿各道路兩側排列；燈桿/燈頭用 MultiMesh，光源由動態光源池提供
	var pole_xf: Array[Transform3D] = []
	var head_xf: Array[Transform3D] = []
	var t := -HALF + 12.0
	while t < HALF - 6.0:
		for axis in ROAD_AXES:
			for side in [-1.0, 1.0]:
				var off: float = side * (ROAD_WIDTH * 0.5 + 0.6)
				_add_lamp(Vector3(axis + off, 0.0, t), -side, true, pole_xf, head_xf)
				_add_lamp(Vector3(t + 12.0, 0.0, axis + off), -side, false, pole_xf, head_xf)
		t += 24.0
	var pole_mesh := BoxMesh.new()
	pole_mesh.size = Vector3(0.15, 5.0, 0.15)
	_add_multimesh(pole_mesh, _make_material(Color(0.14, 0.09, 0.07)), pole_xf)
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.5, 0.15, 0.3)
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.7, 0.62, 0.5)
	head_mat.emission_enabled = true
	head_mat.emission = Color(1.0, 0.75, 0.45)
	head_mat.emission_energy_multiplier = 0.9
	_add_multimesh(head_mesh, head_mat, head_xf)

	for i in LIGHT_POOL_SIZE:
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.72, 0.42)
		light.light_energy = LIGHT_ENERGY
		light.omni_range = 13.0
		light.distance_fade_enabled = true
		light.distance_fade_begin = 30.0
		light.distance_fade_length = 8.0
		add_child(light)
		pool.append(light)
		pool_lamp.append(-1)


func _add_lamp(base: Vector3, inward: float, along_z: bool, poles: Array[Transform3D], heads: Array[Transform3D]) -> void:
	if absf(base.x) > HALF - 2.0 or absf(base.z) > HALF - 2.0:
		return
	var along := base.z if along_z else base.x
	if _in_intersection(along):
		return
	poles.append(Transform3D(Basis.from_euler(Vector3(rng.randf_range(-0.07, 0.07), 0.0, rng.randf_range(-0.07, 0.07))), base + Vector3(0.0, 2.5, 0.0)))
	var head := base + Vector3(0.0, 5.0, 0.0)
	if along_z:
		head.x += inward * 0.6
	else:
		head.z += inward * 0.6
	heads.append(Transform3D(Basis.IDENTITY, head))
	lamp_positions.append(head)


func _assign_lights() -> void:
	if pool.is_empty() or lamp_positions.is_empty():
		return
	var center := Vector3.ZERO
	if player != null:
		center = player.global_position
	var order: Array[int] = []
	for i in lamp_positions.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		return lamp_positions[a].distance_squared_to(center) < lamp_positions[b].distance_squared_to(center))
	# 已在服務最近路燈的光源保持不動，其餘光源改派到尚未被照亮的路燈
	var wanted: Array[int] = []
	wanted.assign(order.slice(0, pool.size()))
	var free_lights: Array[int] = []
	for i in pool.size():
		if wanted.has(pool_lamp[i]):
			wanted.erase(pool_lamp[i])
		else:
			free_lights.append(i)
	for k in mini(free_lights.size(), wanted.size()):
		pool_lamp[free_lights[k]] = wanted[k]
		pool[free_lights[k]].position = lamp_positions[wanted[k]]


func _build_boundary() -> void:
	var body := StaticBody3D.new()
	var e := HALF + 0.5
	var span := HALF * 2.0 + 2.0
	for data in [
		[Vector3(0.0, 5.0, e), Vector3(span, 10.0, 1.0)],
		[Vector3(0.0, 5.0, -e), Vector3(span, 10.0, 1.0)],
		[Vector3(e, 5.0, 0.0), Vector3(1.0, 10.0, span)],
		[Vector3(-e, 5.0, 0.0), Vector3(1.0, 10.0, span)],
	]:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = data[1]
		shape.shape = box
		shape.position = data[0]
		body.add_child(shape)
	add_child(body)
