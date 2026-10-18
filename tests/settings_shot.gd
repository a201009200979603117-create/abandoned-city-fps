extends SceneTree
# 設定頁版面截圖：AC_SAVE=chk godot --path . --resolution 1920x1200 -s tests/settings_shot.gd
# 輸出 settings_<寬>x<高>.png 到 T_OUT（預設 %TEMP%）

func _init() -> void:
	await process_frame
	change_scene_to_file("res://main.tscn")
	for i in 40:
		await process_frame
	var mu = root.get_node("Main/UI").menu_ui
	mu.show_page("settings")
	for i in 20:
		await process_frame
	var out := OS.get_environment("T_OUT") if OS.get_environment("T_OUT") != "" else OS.get_environment("TEMP")
	var sz := root.get_visible_rect().size
	var img := root.get_texture().get_image()
	img.save_png("%s/settings_%dx%d.png" % [out, int(img.get_width()), int(img.get_height())])
	print("[shot] viewport=", sz, " window=", root.size, " scale_mode=", root.content_scale_mode)
	quit()
