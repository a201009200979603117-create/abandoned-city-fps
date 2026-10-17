extends SceneTree
# 大逃殺保底測試：剩 1 個卡住（跳傘中、物理停擺）的 AI，應在決賽圈超時後被淘汰並讓玩家奪冠
#   AC_SAVE=chk godot --headless --path . -s tests/br_stuck_check.gd

var frames: int = 0
var game: Node
var main: Node
var mgr: Node
var stuck: Node


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 2:
		game = root.get_node("Game")
		game.mode = "br"
		game._apply_level(1)
		game.gameplay_boot = true
		game.skip_menu = true
		main = load("res://main.tscn").instantiate()
		root.add_child(main)
		current_scene = main
		return false
	if main == null:
		return false
	if mgr == null:
		mgr = main.get_node_or_null("World/BRManager")
		if mgr == null:
			for n in main.get_tree().get_nodes_in_group("br_bots"):
				mgr = n.get("manager")
				break
		return false
	if not mgr.started:
		return false
	if stuck == null:
		var bots: Array = get_nodes_in_group("br_bots")
		if bots.size() < 11:
			return false
		stuck = bots[0]
		for b in bots.slice(1):
			b.take_damage(9999.0, null)
			b.set("dropping", false)
		stuck.set_physics_process(false)
		stuck.set("dropping", true)
		mgr.landed = true
		mgr.zone_finished = true
		mgr.final_time = 40.0
		print("[chk] alive=", game.br_alive, " 卡住的 AI 跳傘狀態、物理停擺")
		return false
	if frames % 120 == 0:
		print("[chk] alive=", game.br_alive, " final_time=", mgr.final_time, " sudden=", mgr.sudden_death, " victory=", mgr.victory)
	if mgr.victory:
		print("[chk] PASS 奪冠 alive=", game.br_alive)
		quit(0)
		return true
	if frames > 4000:
		print("[chk] FAIL 逾時，alive=", game.br_alive)
		quit(1)
		return true
	return false
