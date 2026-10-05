class_name Hud
extends CanvasLayer
## All 2D game UI. Reads from EventBus/GameState; talks back only via signals.

signal roll_pressed
signal choice_picked(value: int)

const LOG_LINES := 5

var _banner: Label
var _dice_pop: Label
var _status: Label
var _roll_btn: Button
var _choice_box: HBoxContainer
var _cards: VBoxContainer
var _log_label: Label
var _log := PackedStringArray()
var _current_pid := -1


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = PartyTheme.get_theme()
	add_child(root)

	_cards = VBoxContainer.new()
	_cards.position = Vector2(20, 20)
	_cards.add_theme_constant_override("separation", 10)
	root.add_child(_cards)

	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 16
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	var banner_panel := PanelContainer.new()
	banner_panel.add_theme_stylebox_override("panel", PartyTheme.card_style(Color("ffd23d"), true))
	_banner = Label.new()
	_banner.text = "Waiting for players..."
	_banner.add_theme_font_size_override("font_size", 28)
	banner_panel.add_child(_banner)
	top.add_child(banner_panel)

	var leave := Button.new()
	leave.text = "Leave"
	leave.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	leave.offset_left = -130
	leave.offset_top = 16
	leave.offset_right = -20
	leave.pressed.connect(func(): NetworkManager.leave())
	root.add_child(leave)

	_dice_pop = Label.new()
	_dice_pop.add_theme_font_size_override("font_size", 120)
	_dice_pop.add_theme_color_override("font_color", Color("ffd23d"))
	_dice_pop.add_theme_constant_override("outline_size", 22)
	_dice_pop.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_dice_pop.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_dice_pop.grow_vertical = Control.GROW_DIRECTION_BOTH
	_dice_pop.modulate.a = 0.0
	root.add_child(_dice_pop)

	var bottom := VBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -190
	bottom.offset_bottom = -24
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 12)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_choice_box = HBoxContainer.new()
	_choice_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_choice_box.add_theme_constant_override("separation", 14)
	_roll_btn = Button.new()
	_roll_btn.text = "ROLL!"
	_roll_btn.add_theme_font_size_override("font_size", 36)
	_roll_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_roll_btn.disabled = true
	_roll_btn.pressed.connect(func():
		_roll_btn.disabled = true
		roll_pressed.emit())
	for c in [_status, _choice_box, _roll_btn]:
		bottom.add_child(c)

	_log_label = Label.new()
	_log_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_log_label.offset_left = 20
	_log_label.offset_top = -150
	_log_label.offset_bottom = -20
	_log_label.add_theme_font_size_override("font_size", 16)
	_log_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	root.add_child(_log_label)

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
	var mine := GameState.peer_of(pid) == NetworkManager.local_id()
	_banner.text = "Round %d/%d" % [round_no, max_rounds]
	_status.text = "Your turn!" if mine else "%s's turn" % GameState.name_of(pid)
	_roll_btn.disabled = not mine
	_roll_btn.visible = mine
	_refresh_players()


func _on_dice_rolled(pid: int, value: int) -> void:
	_status.text = "%s rolled %d" % [GameState.name_of(pid), value]
	_roll_btn.disabled = true
	_roll_btn.visible = false
	_dice_pop.text = str(value)
	_dice_pop.modulate.a = 1.0
	await get_tree().process_frame
	_dice_pop.pivot_offset = _dice_pop.size / 2
	_dice_pop.scale = Vector2.ONE * 0.2
	var tw := create_tween()
	tw.tween_property(_dice_pop, "scale", Vector2.ONE * 1.25, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_dice_pop, "scale", Vector2.ONE, 0.12)
	tw.tween_interval(0.5)
	tw.tween_property(_dice_pop, "modulate:a", 0.0, 0.3)


func _on_prompt(pid: int, kind: int, options: PackedInt32Array) -> void:
	_clear_choices()
	if GameState.peer_of(pid) != NetworkManager.local_id():
		_status.text = "%s is deciding..." % GameState.name_of(pid)
		return
	_status.text = "Buy a star?" if kind == TurnManager.Prompt.STAR else "Choose your path!"
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
	for c in _cards.get_children():
		c.queue_free()
	for pid in GameState.count():
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", PartyTheme.card_style(GameState.color_of(pid), pid == _current_pid))
		var l := Label.new()
		l.text = "%s\nCoins %d    Stars %d" % [GameState.name_of(pid), GameState.coins[pid], GameState.stars[pid]]
		l.add_theme_font_size_override("font_size", 18)
		card.add_child(l)
		_cards.add_child(card)


func _on_game_over(order: PackedInt32Array) -> void:
	_roll_btn.visible = false
	_clear_choices()
	var lines := PackedStringArray(["GAME OVER!"])
	for i in order.size():
		lines.append("%d. %s - %d stars, %d coins" % [i + 1, GameState.name_of(order[i]), GameState.stars[order[i]], GameState.coins[order[i]]])
	_banner.text = "\n".join(lines)
	_status.text = "%s wins!" % GameState.name_of(order[0])
