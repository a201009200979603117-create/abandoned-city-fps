extends Node
# 以程式合成的簡易音效（不需要任何音檔）

const RATE: int = 22050

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


func play(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not sounds.has(sound_name):
		return
	var p := AudioStreamPlayer.new()
	p.stream = sounds[sound_name]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	add_child(p)
	p.finished.connect(p.queue_free)
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
