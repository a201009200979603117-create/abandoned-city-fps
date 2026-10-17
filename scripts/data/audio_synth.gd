extends RefCounted
# 程式合成音效庫（靜態函式，可在背景執行緒中呼叫）：勝敗樂句、警報、雷聲、雨聲、Boss 氛圍、介面音效

const RATE: int = 22050


static func _wav(buf: PackedFloat32Array, looping: bool, gain: float = 1.0) -> AudioStreamWAV:
	var n := buf.size()
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		bytes.encode_s16(i * 2, int(clampf(tanh(buf[i] * gain), -1.0, 1.0) * 30000.0))
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


static func _wave(kind: String, ph: float) -> float:
	var p := fposmod(ph, 1.0)
	match kind:
		"saw":
			return 2.0 * p - 1.0
		"sq":
			return 1.0 if p < 0.5 else -1.0
		"pulse":
			return 1.0 if p < 0.25 else -1.0
		"tri":
			return 4.0 * absf(p - 0.5) - 1.0
	return sin(TAU * ph)


# notes: [頻率, 起點秒, 長度秒, 音量, 波形, 衰減]
static func render_notes(dur: float, notes: Array) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for ev in notes:
		var f: float = ev[0]
		var st := int(float(ev[1]) * RATE)
		var len := int(float(ev[2]) * RATE)
		var vol: float = ev[3]
		var kind: String = ev[4]
		var decay: float = ev[5]
		var ph := 0.0
		for j in len:
			var i := st + j
			if i >= n:
				break
			var t := float(j) / RATE
			ph += f / RATE
			var rel := minf(float(len - j) / (0.03 * RATE), 1.0)   # 結尾淡出避免爆音
			var env := minf(t / 0.008, 1.0) * exp(-t * decay) * rel
			buf[i] += _wave(kind, ph) * env * vol
	return buf


# ---------- 勝敗 / 波次樂句 ----------

static func win() -> AudioStreamWAV:
	var c4 := 261.63
	var notes: Array = [
		[c4, 0.0, 0.5, 0.2, "sq", 5.0], [c4 * 1.26, 0.12, 0.5, 0.2, "sq", 5.0],
		[c4 * 1.5, 0.24, 0.5, 0.2, "sq", 5.0], [c4 * 2.0, 0.36, 0.6, 0.22, "sq", 4.0],
		[c4 * 2.0, 0.6, 1.8, 0.12, "saw", 1.6], [c4 * 2.52, 0.6, 1.8, 0.1, "saw", 1.6], [c4 * 3.0, 0.6, 1.8, 0.1, "saw", 1.6],
		[c4 * 0.5, 0.6, 1.9, 0.3, "tri", 1.0], [c4 * 4.0, 1.0, 1.0, 0.07, "sin", 2.5],
	]
	return _wav(render_notes(2.6, notes), false, 1.2)


static func lose() -> AudioStreamWAV:
	var notes: Array = [
		[220.0, 0.0, 1.0, 0.18, "saw", 2.0], [174.61, 0.5, 1.0, 0.18, "saw", 2.0],
		[164.81, 1.0, 1.4, 0.18, "saw", 1.8], [123.47, 1.6, 1.4, 0.2, "saw", 1.6],
		[110.0, 0.0, 3.0, 0.26, "tri", 0.7], [116.54, 0.0, 3.0, 0.1, "tri", 0.7],
	]
	return _wav(render_notes(3.2, notes), false, 1.2)


static func wave_clear() -> AudioStreamWAV:
	var g4 := 392.0
	var notes: Array = [
		[g4, 0.0, 0.3, 0.2, "sq", 7.0], [g4 * 1.26, 0.09, 0.3, 0.2, "sq", 7.0],
		[g4 * 1.5, 0.18, 0.3, 0.2, "sq", 7.0], [g4 * 2.0, 0.27, 0.7, 0.2, "sq", 4.0],
	]
	return _wav(render_notes(1.1, notes), false, 1.1)


# ---------- 警報 / 提示音 ----------

static func siren() -> AudioStreamWAV:
	var n := int(2.4 * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := 620.0 + 280.0 * (0.5 - 0.5 * cos(TAU * 0.85 * t))
		ph += f / RATE
		var env := minf(t / 0.05, 1.0) * minf((2.4 - t) / 0.15, 1.0)
		buf[i] = (_wave("tri", ph) * 0.8 + _wave("sin", ph * 2.0) * 0.2) * env * 0.4
	return _wav(buf, false, 1.0)


static func beep() -> AudioStreamWAV:
	return _wav(render_notes(0.14, [[880.0, 0.0, 0.12, 0.35, "sin", 14.0]]), false, 1.0)


static func car_alarm() -> AudioStreamWAV:
	var n := int(3.4 * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var seg := int(t / 0.14)
		var f := 1250.0 if seg % 2 == 0 else 980.0
		f += 120.0 * sin(t * 22.0)
		ph += f / RATE
		var env := minf(t / 0.02, 1.0) * minf((3.4 - t) / 0.2, 1.0)
		buf[i] = _wave("sq", ph) * env * 0.16
	return _wav(buf, false, 1.0)


# ---------- 天氣 ----------

static func thunder() -> AudioStreamWAV:
	var dur := 4.0
	var n := int(dur * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 321
	var lp1 := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var nz := rng.randf_range(-1.0, 1.0)
		lp1 += (nz - lp1) * 0.012
		lp2 += (nz - lp2) * 0.15
		var swell := minf(t / 0.35, 1.0) * exp(-t * 0.85)
		var crack := exp(-t * 28.0) * lp2 * 1.6
		var roll := lp1 * 9.0 * swell * (0.6 + 0.4 * sin(t * 9.0 + sin(t * 3.0) * 2.0))
		buf[i] = crack + roll
	return _wav(buf, false, 0.8)


static func rain() -> AudioStreamWAV:
	var dur := 3.0
	var n := int(dur * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 555
	var lp_a := 0.0
	var lp_b := 0.0
	for i in n:
		var nz := rng.randf_range(-1.0, 1.0)
		lp_a += (nz - lp_a) * 0.55
		lp_b += (nz - lp_b) * 0.08
		var v := (lp_a - lp_b) * 0.55   # 帶通：偏高頻的沙沙聲
		if rng.randf() < 0.0025:
			v += rng.randf_range(0.2, 0.5)   # 偶爾的水滴
		buf[i] = v * 0.5
	return _wav(buf, true, 1.0)


# ---------- Boss 戰氛圍（循環）：低頻持續音 + 不協和弦樂震音 + 不規則重擊 ----------

static func boss_loop() -> AudioStreamWAV:
	var dur := 8.0
	var n := int(dur * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 808
	var p1 := 0.0
	var p2 := 0.0
	var s1 := 0.0
	var s2 := 0.0
	var lp1 := 0.0
	var lp2 := 0.0
	var hits := [0.0, 0.75, 1.5, 2.0, 3.0, 3.75, 4.5, 5.0, 6.0, 6.75]
	for i in n:
		var t := float(i) / RATE
		p1 += 41.2 / RATE
		p2 += 41.9 / RATE
		var drone := (sin(TAU * p1) + sin(TAU * p2)) * 0.2
		s1 += 233.1 / RATE
		s2 += 246.9 / RATE
		lp1 += ((2.0 * fposmod(s1, 1.0) - 1.0) - lp1) * 0.05
		lp2 += ((2.0 * fposmod(s2, 1.0) - 1.0) - lp2) * 0.05
		var trem := 0.5 + 0.5 * sin(TAU * 5.5 * t)
		var strings := (lp1 + lp2) * 0.5 * trem * (0.5 + 0.5 * sin(TAU * t / dur - PI / 2.0))
		var v := drone + strings * 0.6
		for h in hits:
			var dt := t - float(h)
			if dt >= 0.0 and dt < 0.5:
				v += sin(TAU * (55.0 - 18.0 * dt) * dt) * exp(-dt * 8.0) * 0.7
		buf[i] = v
	return _wav(buf, true, 1.0)


# ---------- 介面音效 ----------

static func ui_click() -> AudioStreamWAV:
	return _wav(render_notes(0.09, [[880.0, 0.0, 0.07, 0.3, "sin", 30.0], [1320.0, 0.0, 0.04, 0.12, "sin", 50.0]]), false, 1.0)


static func ui_hover() -> AudioStreamWAV:
	return _wav(render_notes(0.05, [[1500.0, 0.0, 0.035, 0.12, "sin", 60.0]]), false, 1.0)


static func ui_back() -> AudioStreamWAV:
	return _wav(render_notes(0.1, [[620.0, 0.0, 0.08, 0.3, "sin", 28.0], [420.0, 0.03, 0.07, 0.2, "sin", 35.0]]), false, 1.0)
