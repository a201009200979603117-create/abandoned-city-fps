extends SceneTree
# 烘焙音檔：以程式合成產生全部音效與大廳音樂，存成 res://audio/*.wav
#   AC_BAKE=1 godot --path . -s tests/bake_audio.gd
# 完成後請執行 godot --headless --path . --import 讓 Godot 匯入新音檔。

func _init() -> void:
	await process_frame
	var sfx := root.get_node("Sfx")
	var t0 := Time.get_ticks_msec()
	while (not sfx.sounds.has("boss_loop") or sfx.music_stream == null) and Time.get_ticks_msec() - t0 < 90000:
		await process_frame
	DirAccess.make_dir_recursive_absolute("res://audio")
	var count := 0
	for n in sfx.BAKED_NAMES:
		if not sfx.sounds.has(n):
			push_error("缺少音效：" + str(n))
			continue
		(sfx.sounds[n] as AudioStreamWAV).save_to_wav("res://audio/%s.wav" % n)
		count += 1
	(sfx.music_stream as AudioStreamWAV).save_to_wav("res://audio/music_lobby.wav")
	print("已烘焙 ", count + 1, " 個音檔")
	quit()
