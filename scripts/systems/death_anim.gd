extends RefCounted
# 死亡演出：被擊中方向的反方向倒下（帶小幅反彈）、四肢鬆垮、屍體滑行一小段，停留後沉入地面再移除。
# 不使用物理，全部以 Tween 完成，因此在手機上也很輕量。


# body：要倒下的節點（碰撞已關閉）；limbs：四肢樞紐 Node3D 陣列；away：倒下的水平方向（世界座標）
static func play(body: Node3D, away: Vector3, limbs: Array, big: bool = false, linger: float = 5.0) -> void:
	away.y = 0.0
	if away.length() < 0.01:
		away = body.global_transform.basis.z   # 沒有來源就往身後倒
		away.y = 0.0
	away = away.normalized()
	# 倒下的旋轉軸：垂直於倒下方向（水平）
	var axis := Vector3.UP.cross(away).normalized()
	var start_basis := body.global_transform.basis
	var start_pos := body.global_position
	var fall_t := 0.85 if big else 0.5
	var slide := 1.4 if big else 0.9

	var tw := body.create_tween()
	tw.tween_method(func(k: float) -> void:
		if not is_instance_valid(body):
			return
		# 先快後慢，並在末段輕微反彈（超過 90° 再彈回）
		var ang := deg_to_rad(90.0) * (1.0 - pow(1.0 - k, 3.0))
		ang += sin(k * PI) * deg_to_rad(10.0) * k
		body.global_transform.basis = start_basis.rotated(axis, ang).orthonormalized()
		body.global_position = start_pos + away * slide * ease(k, 0.5)
		, 0.0, 1.0, fall_t)

	# 四肢鬆垮：隨機擺向
	for l in limbs:
		var n := l as Node3D
		if n == null or not is_instance_valid(n):
			continue
		var lt := n.create_tween()
		lt.set_parallel(true)
		lt.tween_property(n, "rotation:x", randf_range(-1.1, 0.9), fall_t)
		lt.tween_property(n, "rotation:z", randf_range(-0.7, 0.7), fall_t)

	# 停留 → 沉入地面 → 移除
	tw.tween_interval(linger)
	tw.tween_property(body, "global_position:y", start_pos.y - 1.2, 1.2).set_ease(Tween.EASE_IN)
	tw.tween_callback(body.queue_free)
