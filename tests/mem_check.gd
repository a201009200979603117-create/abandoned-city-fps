extends SceneTree
# 記憶體 / 物件數檢查：記錄選單與遊戲中的節點數、物件數、靜態記憶體、顯存，並偵測長時間遊玩是否持續成長
#   AC_SAVE=<獨立存檔> T_MODE=zombie|br T_SECS=60 godot --path . -s tests/mem_check.gd

func _snap(tag: String) -> void:
	var mb := 1024.0 * 1024.0
	print("[mem] %-10s nodes=%d objects=%d orphans=%d static=%.1fMB vram=%.1fMB draws=%d prims=%d fps=%d" % [
		tag,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		Performance.get_monitor(Performance.MEMORY_STATIC) / mb,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / mb,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		int(Performance.get_monitor(Performance.TIME_FPS))])


func _init() -> void:
	await process_frame
	var mode := OS.get_environment("T_MODE") if OS.get_environment("T_MODE") != "" else "zombie"
	var secs := int(OS.get_environment("T_SECS")) if OS.get_environment("T_SECS") != "" else 60
	var game := root.get_node("Game")
	change_scene_to_file("res://main.tscn")
	await create_timer(2.0).timeout
	_snap("menu")
	game.begin_run(mode, 3)
	await create_timer(3.0).timeout
	var main := root.get_node("Main")
	if mode == "zombie":
		main.get_node("UI")._pick_skill(0)
	var player := main.get_node("Player")
	var t0 := Time.get_ticks_msec()
	var next_report := 0
	while (Time.get_ticks_msec() - t0) / 1000 < secs:
		# 讓玩家保持存活並持續擊殺，模擬長時間遊玩
		if not is_instance_valid(player):
			print("[mem] 場景已重新載入（對局結束），提前結束")
			break
		player.health = player.max_health
		for e in get_nodes_in_group("enemies"):
			if is_instance_valid(e) and not e.is_dead and e.global_position.distance_to(player.global_position) < 9.0:
				e.take_damage(9999.0)
		if (Time.get_ticks_msec() - t0) / 1000 >= next_report:
			_snap("play+%ds" % next_report)
			next_report += 15
		await create_timer(0.25).timeout
	_snap("end")
	quit()
