extends Node
# 以程式合成的簡易音效（不需要任何音檔）

const RATE: int = 22050
const AudioSynth = preload("res://scripts/data/audio_synth.gd")

var sounds: Dictionary = {}
var ambient_player: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	sounds["shoot"] = _synth(0.22, _gen_shoot)
	sounds["empty"] = _synth(0.06, _gen_empty)
	sounds["reload"] = _synth(0.6, _gen_reload)
	sounds["hit"] = _synth(0.09, _gen_hit)
	sounds["die"] = _synth(0.45, _gen_die)
	sounds["hurt"] = _synth(0.3, _gen_hurt)
	sounds["pickup"] = _synth(0.3, _gen_pickup)
	sounds["wave"] = _synth(0.9, _gen_wave)
	sounds["win"] = _synth(1.0, _gen_win)
	sounds["lose"] = _synth(1.2, _gen_lose)
	sounds["step"] = _synth(0.1, _gen_step)
	sounds["ambient"] = _make_ambient(4.0)
	_init_audio_extras.call_deferred()


const MAX_VOICES: int = 4   # 同一種音效最多同時發聲數，播放器會重複使用（避免連射時不斷建立/釋放節點）
var voices: Dictionary = {}
var voice_next: Dictionary = {}


func play(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not sounds.has(sound_name):
		return
	var pool: Array = voices.get(sound_name, [])
	if not voices.has(sound_name):
		voices[sound_name] = pool
		voice_next[sound_name] = 0
	var p: AudioStreamPlayer = null
	for v in pool:
		if not (v as AudioStreamPlayer).playing:
			p = v
			break
	if p == null:
		if pool.size() < MAX_VOICES:
			p = AudioStreamPlayer.new()
			p.stream = sounds[sound_name]
			add_child(p)
			pool.append(p)
		else:
			var i: int = voice_next[sound_name]
			voice_next[sound_name] = (i + 1) % pool.size()
			p = pool[i]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


func start_ambient() -> void:
	if ambient_player != null:
		return
	ambient_player = AudioStreamPlayer.new()
	ambient_player.stream = sounds["ambient"]
	ambient_player.volume_db = -14.0
	add_child(ambient_player)
	ambient_player.play()


func _synth(duration: float, gen: Callable) -> AudioStreamWAV:
	var n: int = int(duration * RATE)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var v: float = clampf(gen.call(float(i) / RATE), -1.0, 1.0)
		bytes.encode_s16(i * 2, int(v * 32000.0))
	return _wav(bytes, false, n)


func _wav(bytes: PackedByteArray, looping: bool, n: int) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	if looping:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = n
	return wav


func _noise() -> float:
	return randf_range(-1.0, 1.0)


func _gen_shoot(t: float) -> float:
	return _noise() * exp(-t * 26.0) * 0.7 + sin(TAU * 85.0 * t) * exp(-t * 18.0) * 0.7


func _gen_empty(t: float) -> float:
	return _noise() * exp(-t * 150.0) * 0.5


func _click(x: float) -> float:
	if x < 0.0:
		return 0.0
	return _noise() * exp(-x * 90.0) * 0.6 + sin(TAU * 400.0 * x) * exp(-x * 60.0) * 0.3


func _gen_reload(t: float) -> float:
	return _click(t) + _click(t - 0.35)


func _gen_hit(t: float) -> float:
	return sin(TAU * 900.0 * t) * exp(-t * 50.0) * 0.5


func _gen_die(t: float) -> float:
	return sin(TAU * (200.0 * t - 150.0 * t * t)) * exp(-t * 5.0) * 0.6 + _noise() * exp(-t * 20.0) * 0.3


func _gen_hurt(t: float) -> float:
	return sin(TAU * 60.0 * t) * exp(-t * 9.0) * 0.9 + _noise() * exp(-t * 35.0) * 0.4


func _gen_pickup(t: float) -> float:
	var f: float = 520.0
	if t >= 0.2:
		f = 880.0
	elif t >= 0.1:
		f = 660.0
	return sin(TAU * f * t) * exp(-fmod(t, 0.1) * 12.0) * 0.4


func _gen_wave(t: float) -> float:
	var env: float = minf(t * 20.0, 1.0) * exp(-t * 2.5)
	return (sin(TAU * 110.0 * t) + 0.5 * sin(TAU * 165.0 * t)) * env * 0.5


func _gen_win(t: float) -> float:
	var notes: Array[float] = [523.0, 659.0, 784.0, 1047.0]
	var idx: int = mini(int(t / 0.2), 3)
	return sin(TAU * notes[idx] * t) * exp(-fmod(t, 0.2) * 4.0) * 0.4


func _gen_lose(t: float) -> float:
	return sin(TAU * (300.0 * t - 125.0 * t * t)) * exp(-t * 2.0) * 0.6


func _gen_step(t: float) -> float:
	return _noise() * exp(-t * 50.0) * 0.25 + sin(TAU * 70.0 * t) * exp(-t * 40.0) * 0.4


func _make_ambient(duration: float) -> AudioStreamWAV:
	var n: int = int(duration * RATE)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var lp: float = 0.0
	for i in n:
		var t: float = float(i) / RATE
		lp += (_noise() - lp) * 0.04
		var env: float = 0.5 + 0.5 * sin(TAU * t / duration - PI / 2.0)
		var v: float = lp * 2.2 * (0.4 + 0.6 * env)
		bytes.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32000.0))
	return _wav(bytes, true, n)


# =====================================================================
# 背景音樂與環境音
#   大廳：程式合成的快節奏電子曲（背景執行緒生成，完成後自動播放）
#   遊戲中：停止音樂，只留風聲、遠方喪屍嘶吼、遠處槍響、低血量心跳
# =====================================================================

const MUSIC_RATE: int = 16000
const MUSIC_BPM: float = 140.0
const MUSIC_BARS: int = 8

var music_player: AudioStreamPlayer
var music_stream: AudioStreamWAV = null
var music_wanted: bool = false
var music_thread: Thread = null
var music_tween: Tween
var music_bus: int = -1

# 合成用的暫存（各階段共用）
var m_n: int = 0
var m_step: int = 0
var m_others: PackedFloat32Array
var m_kick: PackedFloat32Array
var m_rng := RandomNumberGenerator.new()

var voices3d: Array = []
var amb_timer: float = 4.0
var far_timer: float = 8.0
var heart_timer: float = 0.0
var player_ref: Node3D = null

# 背景生成的額外音效（勝敗樂句、警報、雷雨、Boss 氛圍…）完成後才併入 sounds
var pending_sounds: Dictionary = {}
var rain_player: AudioStreamPlayer
var boss_player: AudioStreamPlayer
var rain_wanted: float = 0.0
var boss_wanted: bool = false
var alarm_timer: float = 40.0


func _init_audio_extras() -> void:
	# 音樂專用 Bus，讓設定頁可以單獨調整音樂音量
	if AudioServer.get_bus_index("Music") == -1:
		AudioServer.add_bus()
		music_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(music_bus, "Music")
		AudioServer.set_bus_send(music_bus, "Master")
	else:
		music_bus = AudioServer.get_bus_index("Music")
	apply_music_volume()

	music_player = AudioStreamPlayer.new()
	music_player.bus = "Music"
	music_player.volume_db = -80.0
	add_child(music_player)

	sounds["groan1"] = _make_groan(1.9, 118.0, 66.0, 0.22, 520.0, 980.0, 0.5)
	sounds["groan2"] = _make_groan(1.4, 150.0, 92.0, 0.3, 640.0, 1250.0, 0.55)
	sounds["groan3"] = _make_groan(2.4, 95.0, 58.0, 0.38, 430.0, 820.0, 0.65)
	sounds["screech"] = _make_groan(1.1, 360.0, 620.0, 0.35, 950.0, 2100.0, 0.7)
	sounds["roar"] = _make_groan(2.6, 82.0, 52.0, 0.45, 380.0, 760.0, 0.75)
	sounds["heartbeat"] = _synth(0.7, _gen_heartbeat)
	sounds["hit_head"] = _synth(0.16, _gen_hit_head)
	sounds["kill_ding"] = _synth(0.35, _gen_kill_ding)
	sounds["explosion"] = _make_explosion()
	sounds["grenade_pin"] = _synth(0.12, _gen_empty)
	sounds["far_shot"] = _make_far_shot()
	# 輕量的介面音效：立即產生
	sounds["ui_click"] = AudioSynth.ui_click()
	sounds["ui_hover"] = AudioSynth.ui_hover()
	sounds["ui_back"] = AudioSynth.ui_back()
	sounds["beep"] = AudioSynth.beep()
	rain_player = AudioStreamPlayer.new()
	rain_player.volume_db = -80.0
	add_child(rain_player)
	boss_player = AudioStreamPlayer.new()
	boss_player.volume_db = -80.0
	add_child(boss_player)
	Game.wave_cleared.connect(func(_w: int) -> void: play("wave_clear", -2.0))
	Game.boss_changed.connect(func(b: Node) -> void: set_boss_music(b != null))

	Game.state_changed.connect(_on_game_state)
	Game.wave_started.connect(func(_w: int) -> void:
		play("roar", -4.0, randf_range(0.9, 1.05)))
	_start_music_build()
	_on_game_state(Game.state)


func apply_music_volume() -> void:
	if music_bus < 0:
		return
	var v := clampf(Save.music_volume, 0.0, 1.0)
	AudioServer.set_bus_volume_db(music_bus, linear_to_db(maxf(v, 0.0001)))
	AudioServer.set_bus_mute(music_bus, v <= 0.001)


# ---------- 狀態切換 ----------

func _on_game_state(s: int) -> void:
	match s:
		Game.State.MENU:
			_set_music(true)
			_pause_loops(true)
			if ambient_player != null:
				ambient_player.stream_paused = true
		Game.State.PLAYING:
			_set_music(false)
			if ambient_player != null:
				ambient_player.stream_paused = false
			_pause_loops(false)
		_:
			# 暫停 / 選技能 / 結算：環境音暫停，音樂保持關閉
			if ambient_player != null:
				ambient_player.stream_paused = true
			_pause_loops(true)


func _pause_loops(paused: bool) -> void:
	if rain_player != null:
		rain_player.stream_paused = paused
	if boss_player != null:
		boss_player.stream_paused = paused


# ---------- 雨聲 / Boss 氛圍 / 雷聲 ----------

func start_rain(intensity: float) -> void:
	rain_wanted = intensity
	if rain_player == null or not sounds.has("rain"):
		return   # 尚在生成，完成後會自動開始
	if intensity <= 0.0:
		rain_player.stop()
		return
	rain_player.stream = sounds["rain"]
	rain_player.volume_db = lerpf(-30.0, -12.0, clampf(intensity, 0.0, 1.0))
	if not rain_player.playing:
		rain_player.play()


func stop_rain() -> void:
	start_rain(0.0)


func set_boss_music(on: bool) -> void:
	boss_wanted = on
	if boss_player == null or not sounds.has("boss_loop"):
		return
	if on:
		boss_player.stream = sounds["boss_loop"]
		boss_player.volume_db = -14.0
		if not boss_player.playing:
			boss_player.play()
	else:
		var tw := create_tween()
		tw.tween_property(boss_player, "volume_db", -60.0, 1.5)
		tw.tween_callback(boss_player.stop)


# 雷聲：依距離延遲（閃電後 0.3~2 秒）
func thunder(delay: float = 0.6) -> void:
	await get_tree().create_timer(delay).timeout
	play("thunder", -4.0, randf_range(0.85, 1.1))


func _set_music(on: bool) -> void:
	music_wanted = on
	if music_player == null:
		return
	if music_tween != null:
		music_tween.kill()
	if on:
		if music_stream == null:
			return   # 尚在生成，完成後會自動播放
		if not music_player.playing:
			music_player.stream = music_stream
			music_player.volume_db = -40.0
			music_player.play()
		music_tween = create_tween()
		music_tween.tween_property(music_player, "volume_db", -3.0, 1.2)
	else:
		music_tween = create_tween()
		music_tween.tween_property(music_player, "volume_db", -60.0, 0.8)
		music_tween.tween_callback(music_player.stop)


func _process(delta: float) -> void:
	# 背景生成完成 → 接收音樂
	if music_thread != null and not music_thread.is_alive():
		music_thread.wait_to_finish()
		music_thread = null
		_finish_music()
	if not Game.is_playing():
		return
	_ambient_events(delta)


# ---------- 遊戲中環境音 ----------

func _ambient_events(delta: float) -> void:
	if player_ref == null or not is_instance_valid(player_ref):
		player_ref = get_tree().get_first_node_in_group("player") as Node3D
		if player_ref == null:
			return
	# 遠方喪屍嘶吼；大逃殺則是偶爾傳來、較小聲
	amb_timer -= delta
	if amb_timer <= 0.0:
		amb_timer = randf_range(5.0, 11.0) if not Game.is_br() else randf_range(14.0, 28.0)
		var names := ["groan1", "groan2", "groan3", "groan1", "screech"]
		var d := randf_range(28.0, 60.0)
		play3d(names.pick_random(), _around_player(d), -2.0 if not Game.is_br() else -8.0, randf_range(0.85, 1.15))
	# 大逃殺：遠處槍聲
	if Game.is_br():
		far_timer -= delta
		if far_timer <= 0.0:
			far_timer = randf_range(5.0, 14.0)
			play3d("far_shot", _around_player(randf_range(60.0, 110.0)), -4.0, randf_range(0.8, 1.2))
	# 遠方的汽車警報器（偶爾）
	alarm_timer -= delta
	if alarm_timer <= 0.0:
		alarm_timer = randf_range(45.0, 100.0)
		play3d("car_alarm", _around_player(randf_range(55.0, 100.0)), -6.0, randf_range(0.9, 1.1))
	# 低血量心跳
	var hp := float(player_ref.get("health"))
	var mx := maxf(float(player_ref.get("max_health")), 1.0)
	if hp > 0.0 and hp / mx < 0.3:
		heart_timer -= delta
		if heart_timer <= 0.0:
			heart_timer = lerpf(0.55, 1.0, (hp / mx) / 0.3)
			play("heartbeat", -2.0)
	else:
		heart_timer = 0.0


func _around_player(dist: float) -> Vector3:
	var a := randf() * TAU
	return player_ref.global_position + Vector3(cos(a) * dist, 1.5, sin(a) * dist)


# 立體定位音效（距離越遠越小聲、越悶）；同時最多 6 個
func play3d(sound_name: String, pos: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not sounds.has(sound_name):
		return
	var p: AudioStreamPlayer3D = null
	for v in voices3d:
		if not (v as AudioStreamPlayer3D).playing:
			p = v
			break
	if p == null:
		if voices3d.size() >= 6:
			return
		p = AudioStreamPlayer3D.new()
		p.unit_size = 14.0
		p.max_distance = 140.0
		p.attenuation_filter_cutoff_hz = 3500.0
		add_child(p)
		voices3d.append(p)
	p.stream = sounds[sound_name]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.global_position = pos
	p.play()


# ---------- 合成：喪屍嘶吼 / 心跳 / 遠方槍聲 ----------

# 鋸齒波聲源 + 雙共振峰濾波（母音感）+ 顫音 + 喉音抖動 + 氣音
func _make_groan(dur: float, f_start: float, f_end: float, rough: float, fm1: float, fm2: float, drive: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(f_start * 13.0 + dur * 1000.0)
	var phase := 0.0
	var lo1 := 0.0
	var bp1 := 0.0
	var lo2 := 0.0
	var bp2 := 0.0
	var k1 := 2.0 * sin(PI * fm1 / RATE)
	var k2 := 2.0 * sin(PI * fm2 / RATE)
	for i in n:
		var t := float(i) / RATE
		var k := t / dur
		var env := minf(k / 0.16, 1.0) * pow(clampf((1.0 - k) / 0.45, 0.0, 1.0), 0.8)
		var f := lerpf(f_start, f_end, k) * (1.0 + 0.035 * sin(TAU * 5.2 * t) + 0.02 * sin(TAU * 11.0 * t))
		phase += f / RATE
		var saw := 2.0 * fposmod(phase, 1.0) - 1.0
		var gurgle := 0.65 + 0.35 * sin(TAU * (24.0 + 6.0 * sin(t * 3.0)) * t)
		var src := (saw * (1.0 - rough) + rng.randf_range(-1.0, 1.0) * rough) * gurgle
		# 共振峰（狀態變數濾波）
		var hi1 := src - lo1 - 0.18 * bp1
		bp1 += k1 * hi1
		lo1 += k1 * bp1
		var hi2 := src - lo2 - 0.22 * bp2
		bp2 += k2 * hi2
		lo2 += k2 * bp2
		var v := (bp1 * 0.9 + bp2 * 0.55) * 0.5 * env
		v = tanh(v * (1.0 + drive * 3.0)) * 0.85
		bytes.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32000.0))
	return _wav(bytes, false, n)


func _gen_hit_head(t: float) -> float:
	# 清脆的金屬爆頭聲：高頻鈴音 + 短促衝擊
	return (sin(TAU * 1850.0 * t) * 0.45 + sin(TAU * 1240.0 * t) * 0.3) * exp(-t * 28.0) + _noise() * exp(-t * 90.0) * 0.35


func _gen_kill_ding(t: float) -> float:
	var f := 880.0 if t < 0.08 else 1320.0
	return sin(TAU * f * t) * exp(-t * 10.0) * 0.45 + sin(TAU * 110.0 * t) * exp(-t * 20.0) * 0.5


func _make_explosion() -> AudioStreamWAV:
	var dur := 1.3
	var n := int(dur * RATE)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * (0.35 * exp(-t * 3.0) + 0.04)
		var v := lp * exp(-t * 3.6) * 2.2 + sin(TAU * (70.0 - 30.0 * t) * t) * exp(-t * 5.0) * 0.9
		bytes.encode_s16(i * 2, int(clampf(v * 0.7, -1.0, 1.0) * 32000.0))
	return _wav(bytes, false, n)


func _gen_heartbeat(t: float) -> float:
	var a := sin(TAU * 52.0 * t) * exp(-t * 14.0)
	var t2 := t - 0.26
	var b := 0.0
	if t2 > 0.0:
		b = sin(TAU * 44.0 * t2) * exp(-t2 * 16.0) * 0.75
	return (a + b) * 0.9


func _make_far_shot() -> AudioStreamWAV:
	var dur := 1.4
	var n := int(dur * RATE)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.09
		var v := lp * exp(-t * 7.0) * 2.4 + sin(TAU * 62.0 * t) * exp(-t * 9.0) * 0.5
		# 回音（遠處建築反射）
		var t2 := t - 0.23
		if t2 > 0.0:
			v += lp * exp(-t2 * 9.0) * 0.9
		var t3 := t - 0.52
		if t3 > 0.0:
			v += lp * exp(-t3 * 11.0) * 0.5
		bytes.encode_s16(i * 2, int(clampf(v * 0.6, -1.0, 1.0) * 32000.0))
	return _wav(bytes, false, n)


# ---------- 合成：大廳音樂（A 小調，140 BPM，8 小節） ----------

func _start_music_build() -> void:
	m_step = int(round(60.0 / MUSIC_BPM / 4.0 * MUSIC_RATE))
	m_n = m_step * 16 * MUSIC_BARS
	if not OS.has_feature("web"):
		music_thread = Thread.new()
		music_thread.start(_music_all_stages)
	else:
		_music_staged_main()


func _extra_builders() -> Array:
	return [
		["win", AudioSynth.win], ["lose", AudioSynth.lose], ["wave_clear", AudioSynth.wave_clear],
		["siren", AudioSynth.siren], ["thunder", AudioSynth.thunder], ["rain", AudioSynth.rain],
		["car_alarm", AudioSynth.car_alarm], ["boss_loop", AudioSynth.boss_loop],
	]


func _music_all_stages() -> void:
	for s in 7:
		_music_stage(s)
	for e in _extra_builders():
		pending_sounds[e[0]] = (e[1] as Callable).call()


# 沒有執行緒（例如網頁版）：每幀只做一個階段，避免卡畫面
func _music_staged_main() -> void:
	for s in 7:
		await get_tree().process_frame
		_music_stage(s)
	for e in _extra_builders():
		await get_tree().process_frame
		pending_sounds[e[0]] = (e[1] as Callable).call()
	_finish_music()


func _finish_music() -> void:
	# 併入背景生成的額外音效
	for k in pending_sounds:
		sounds[k] = pending_sounds[k]
	pending_sounds = {}
	if rain_wanted > 0.0:
		start_rain(rain_wanted)
	if boss_wanted:
		set_boss_music(true)
	if m_kick.size() != m_n:
		return
	var bytes := PackedByteArray()
	bytes.resize(m_n * 2)
	var beat := float(m_step * 4)
	for i in m_n:
		var tb := fposmod(float(i), beat) / float(MUSIC_RATE)
		var duck := 1.0 - 0.55 * exp(-tb * 9.0)   # 側鏈壓縮感：大鼓一響其他聲部讓位
		var v := m_others[i] * duck + m_kick[i]
		v = tanh(v * 1.25) * 0.92
		bytes.encode_s16(i * 2, int(v * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MUSIC_RATE
	wav.stereo = false
	wav.data = bytes
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = m_n
	music_stream = wav
	m_others = PackedFloat32Array()
	m_kick = PackedFloat32Array()
	if music_wanted:
		_set_music(true)


func _step_t(step_index: int) -> int:
	return step_index * m_step


func _music_stage(s: int) -> void:
	var R := float(MUSIC_RATE)
	var total_steps := 16 * MUSIC_BARS
	match s:
		0:
			m_others = PackedFloat32Array()
			m_others.resize(m_n)
			m_kick = PackedFloat32Array()
			m_kick.resize(m_n)
			m_rng.seed = 4242
		1:
			# 大鼓：每拍一下，每四小節最後加花
			for st in total_steps:
				var bar_step := st % 16
				var bar := st / 16
				var hit := bar_step % 4 == 0 or (bar % 4 == 3 and bar_step == 14)
				if not hit:
					continue
				var start := _step_t(st)
				var len := int(0.26 * R)
				var ph := 0.0
				for j in len:
					if start + j >= m_n:
						break
					var t := float(j) / R
					var f := 46.0 + 120.0 * exp(-t * 22.0)
					ph += f / R
					var v := sin(TAU * ph) * exp(-t * 8.0) * 0.95
					if j < 90:
						v += (m_rng.randf() * 2.0 - 1.0) * 0.25 * (1.0 - float(j) / 90.0)
					m_kick[start + j] += v
		2:
			# 軍鼓：第 2、4 拍；最後一小節後半 16 分音符滾奏漸強
			for st in total_steps:
				var bar_step := st % 16
				var bar := st / 16
				var roll := bar == MUSIC_BARS - 1 and bar_step >= 8
				if not (bar_step == 4 or bar_step == 12 or roll):
					continue
				var gain := 0.5
				if roll:
					gain = 0.25 + 0.5 * float(bar_step - 8) / 8.0
				var start := _step_t(st)
				var len := int(0.2 * R)
				for j in len:
					if start + j >= m_n:
						break
					var t := float(j) / R
					var v := (m_rng.randf() * 2.0 - 1.0) * exp(-t * 15.0) * 0.55 + sin(TAU * 190.0 * t) * exp(-t * 26.0) * 0.4
					m_others[start + j] += v * gain
		3:
			# 踩鑔：每個 16 分音符一下，反拍加開放鑔
			var prev := 0.0
			for st in total_steps:
				var bar_step := st % 16
				var open := bar_step % 4 == 2
				var start := _step_t(st)
				var len := int((0.14 if open else 0.045) * R)
				var amp := 0.2 if (bar_step % 2 == 0 or open) else 0.11
				for j in len:
					if start + j >= m_n:
						break
					var t := float(j) / R
					var nz := m_rng.randf() * 2.0 - 1.0
					var hp := nz - prev   # 簡易高通
					prev = nz
					m_others[start + j] += hp * exp(-t * (16.0 if open else 70.0)) * amp
		4:
			# 低音：A 小調進行 Am | F | G | E（各兩小節），搖滾式切分
			var roots := [110.0, 87.31, 98.0, 82.41]
			var hits := [0, 2, 3, 6, 8, 10, 11, 14]
			for bar in MUSIC_BARS:
				var root: float = roots[(bar / 2) % 4]
				for h in hits:
					var st: int = bar * 16 + h
					var f: float = root * (2.0 if (h == 6 or h == 14) else 1.0)
					var start := _step_t(st)
					var len := int(float(m_step) * 1.7)
					var ph := 0.0
					var lp := 0.0
					for j in len:
						if start + j >= m_n:
							break
						var t := float(j) / R
						ph += f / R
						var saw := 2.0 * fposmod(ph, 1.0) - 1.0
						var sq := 1.0 if fposmod(ph, 1.0) < 0.5 else -1.0
						lp += ((saw * 0.6 + sq * 0.4) - lp) * (0.12 + 0.2 * exp(-t * 12.0))
						var env := minf(float(j) / 60.0, 1.0) * exp(-t * 4.5)
						m_others[start + j] += lp * env * 0.55
		5:
			# 琶音主旋律（脈衝波）：第 3 小節開始進入，層層堆疊
			var chords := [
				[220.0, 261.63, 329.63, 440.0],     # Am
				[174.61, 220.0, 261.63, 349.23],    # F
				[196.0, 246.94, 293.66, 392.0],     # G
				[164.81, 207.65, 246.94, 329.63],   # E
			]
			var pat := [0, 1, 2, 3, 2, 1, 2, 3, 0, 1, 2, 3, 2, 1, 3, 2]
			for bar in range(2, MUSIC_BARS):
				var chord: Array = chords[(bar / 2) % 4]
				for k in 16:
					var f: float = chord[pat[k]] * (2.0 if (bar >= 6 and k % 4 == 3) else 1.0)
					var st: int = bar * 16 + k
					var start := _step_t(st)
					var len := int(float(m_step) * 2.2)
					var ph := 0.0
					for j in len:
						if start + j >= m_n:
							break
						var t := float(j) / R
						ph += f / R
						var duty := 0.25 + 0.1 * sin(t * 14.0)
						var pulse := 1.0 if fposmod(ph, 1.0) < duty else -1.0
						var env := minf(float(j) / 40.0, 1.0) * exp(-t * 9.0)
						m_others[start + j] += pulse * env * 0.1
		6:
			# 上升掃頻（最後一小節）：進入下一輪循環前的緊張感
			var start := _step_t(16 * (MUSIC_BARS - 1))
			var len := m_n - start
			var lp2 := 0.0
			for j in len:
				var k := float(j) / float(len)
				lp2 += ((m_rng.randf() * 2.0 - 1.0) - lp2) * (0.03 + 0.6 * k * k)
				m_others[start + j] += lp2 * k * k * 0.5
