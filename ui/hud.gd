class_name Hud
extends CanvasLayer
## All 2D game UI. Reads from EventBus/GameState; talks back only via signals.

signal roll_pressed
signal choice_picked(value: int)

const LOG_LINES := 5

var _turn_label: Label
var _dice_label: Label
var _roll_btn: Button
var _choice_box: HBoxContainer
var _players_box: VBoxContainer
var _log_label: Label
var _log := PackedStringArray()
var _current_pid := -1


func _ready() -> void:
	var left := VBoxContainer.new()
	left.position = Vector2(20, 16)
	add_child(left)
	_turn_label = Label.new()
	_turn_label.text = "Waiting for players..."
	_dice_label = Label.new()
	_roll_btn = Button.new()
	_roll_btn.text = "Roll"
	_roll_btn.disabled = true
	_roll_btn.pressed.connect(func():
		_roll_btn.disabled = true
		roll_pressed.emit())
	_choice_box = HBoxContainer.new()
	_players_box = VBoxContainer.new()
	var leave := Button.new()
	leave.text = "Leave"
	leave.pressed.connect(func(): NetworkManager.leave())
	for c in [_turn_label, _dice_label, _roll_btn, _choice_box, _players_box, leave]:
		left.add_child(c)

	_log_label = Label.new()
	_log_label.anchor_top = 1.0
	_log_label.anchor_bottom = 1.0
	_log_label.offset_left = 20
	_log_label.offset_top = -120
	add_child(_log_label)

	EventBus.turn_started.connect(_on_turn_started)
	EventBus.dice_rolled.connect(_on_dice_rolled)
	EventBus.prompt.connect(_on_prompt)
	EventBus.pawn_moved.connect(func(_p, _s): _clear_choices())
	EventBus.stats_changed.connect(_refresh_players)
	EventBus.log_message.connect(_on_log)
	EventBus.game_over.connect(_on_game_over)
	_refresh_players()


func _on_turn_started(pid: int, round_no: int, max_rounds: int) -> void:
	_current_pid = pid
	_turn_label.text = "Round %d/%d - %s's turn" % [round_no, max_rounds, GameState.name_of(pid)]
	_roll_btn.disabled = GameState.peer_of(pid) != NetworkManager.local_id()
	_refresh_players()


func _on_dice_rolled(pid: int, value: int) -> void:
	_dice_label.text = "%s rolled %d" % [GameState.name_of(pid), value]
	_roll_btn.disabled = true


func _on_prompt(pid: int, kind: int, options: PackedInt32Array) -> void:
	_clear_choices()
	if GameState.peer_of(pid) != NetworkManager.local_id():
		_dice_label.text = "%s is deciding..." % GameState.name_of(pid)
		return
	for i in options.size():
		var b := Button.new()
		if kind == TurnManager.Prompt.STAR:
			b.text = "Buy Star (%d coins)" % SpaceEffects.STAR_COST if options[i] == 1 else "Skip"
		else:
			b.text = "Path %d" % (i + 1)
		b.pressed.connect(func():
			_clear_choices()
			choice_picked.emit(options[i]))
		_choice_box.add_child(b)


func _clear_choices() -> void:
	for b in _choice_box.get_children():
		b.queue_free()


func _on_log(text: String) -> void:
	_log.append(text)
	if _log.size() > LOG_LINES:
		_log.remove_at(0)
	_log_label.text = "\n".join(_log)


func _refresh_players() -> void:
	for c in _players_box.get_children():
		c.queue_free()
	for pid in GameState.count():
		var l := Label.new()
		l.text = "%s%s   coins %d   stars %d" % [">" if pid == _current_pid else " ", GameState.name_of(pid), GameState.coins[pid], GameState.stars[pid]]
		l.add_theme_color_override("font_color", GameState.color_of(pid))
		_players_box.add_child(l)


func _on_game_over(order: PackedInt32Array) -> void:
	_roll_btn.disabled = true
	_clear_choices()
	var lines := PackedStringArray(["Game over!"])
	for i in order.size():
		lines.append("%d. %s - %d stars, %d coins" % [i + 1, GameState.name_of(order[i]), GameState.stars[order[i]], GameState.coins[order[i]]])
	_turn_label.text = "\n".join(lines)
