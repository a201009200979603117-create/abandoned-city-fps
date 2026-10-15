extends Node
# 全域遊戲狀態：分數、波次、暫停/勝負

signal state_changed(new_state: int)
signal wave_started(wave: int)
signal wave_cleared(wave: int)
signal hit_marker(killed: bool)

enum State { MENU, PLAYING, PAUSED, WON, LOST }

var state: State = State.MENU
var score: int = 0
var kills: int = 0
var wave: int = 0
var total_waves: int = 5
var enemies_remaining: int = 0
var skip_menu: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_register_inputs()


func _register_inputs() -> void:
	if InputMap.has_action("sprint"):
		return
	InputMap.add_action("sprint")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_SHIFT
	InputMap.action_add_event("sprint", ev)


func reset() -> void:
	score = 0
	kills = 0
	wave = 0
	enemies_remaining = 0
	set_state(State.MENU)


func set_state(new_state: State) -> void:
	state = new_state
	get_tree().paused = new_state != State.PLAYING
	if new_state == State.PLAYING:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	state_changed.emit(new_state)


func is_playing() -> bool:
	return state == State.PLAYING


func add_kill(points: int) -> void:
	kills += 1
	score += points


func win() -> void:
	if state != State.PLAYING:
		return
	Sfx.play("win")
	set_state(State.WON)


func lose() -> void:
	if state != State.PLAYING:
		return
	Sfx.play("lose")
	set_state(State.LOST)
