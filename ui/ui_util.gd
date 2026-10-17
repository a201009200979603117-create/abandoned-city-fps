extends RefCounted
# 手機版面共用工具：安全區（瀏海 / 圓角 / 手勢條）換算成視窗座標

# 回傳 (左, 上, 右, 下) 縮排。桌機一律為 0；手機至少保留 12 的邊距
static func safe_insets(ctrl: Node) -> Vector4:
	if not Save.touch_mode:
		return Vector4.ZERO
	var out := Vector4(12.0, 8.0, 12.0, 8.0)
	if not OS.has_feature("mobile"):
		return out
	var win := DisplayServer.window_get_size()
	if win.x <= 0 or win.y <= 0:
		return out
	var safe := DisplayServer.get_display_safe_area()
	var vp := ctrl.get_viewport().get_visible_rect().size
	var sx := vp.x / float(win.x)
	var sy := vp.y / float(win.y)
	out.x = maxf(out.x, float(safe.position.x) * sx)
	out.y = maxf(out.y, float(safe.position.y) * sy)
	out.z = maxf(out.z, float(win.x - safe.end.x) * sx)
	out.w = maxf(out.w, float(win.y - safe.end.y) * sy)
	return out
