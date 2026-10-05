extends Control
## Menu + lobby. Pure UI: all session logic lives in NetworkManager.
## Test flags (after `--`): --host  |  --join=<ip>  |  --autostart

var _name_edit: LineEdit
var _addr_edit: LineEdit
var _status: Label
var _roster: Label
var _host_btn: Button
var _join_btn: Button
var _start_btn: Button
var _leave_btn: Button


func _ready() -> void:
	_build_ui()
	NetworkManager.lobby_changed.connect(_refresh)
	if "--autostart" in OS.get_cmdline_user_args():
		NetworkManager.lobby_changed.connect(func():
			if NetworkManager.is_host() and NetworkManager.players.size() >= 2:
				NetworkManager.start_game())
	NetworkManager.join_failed.connect(func(r): _status.text = r)
	_status.text = NetworkManager.last_message
	_refresh()
	for arg in OS.get_cmdline_user_args():
		if arg == "--host":
			_on_host()
		elif arg.begins_with("--join="):
			_addr_edit.text = arg.substr(7)
			_on_join()


func _build_ui() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(320, 0)
	center.add_child(box)
	var title := Label.new()
	title.text = "PARTYGAME"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Your name"
	_name_edit.text = "Player%d" % (randi() % 100)
	_addr_edit = LineEdit.new()
	_addr_edit.text = "127.0.0.1"
	_host_btn = _button("Host", _on_host)
	_join_btn = _button("Join", _on_join)
	_start_btn = _button("Start Game", func(): NetworkManager.start_game())
	_leave_btn = _button("Leave Lobby", func(): NetworkManager.leave(false))
	_roster = Label.new()
	_status = Label.new()
	for c in [title, _name_edit, _addr_edit, _host_btn, _join_btn, _roster, _start_btn, _leave_btn, _status]:
		box.add_child(c)


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b


func _on_host() -> void:
	var err := NetworkManager.host(_name_edit.text)
	_status.text = "Hosting on port %d" % NetworkManager.DEFAULT_PORT if err == OK else "Host failed: %s" % error_string(err)


func _on_join() -> void:
	var err := NetworkManager.join(_addr_edit.text.strip_edges(), _name_edit.text)
	_status.text = "Connecting..." if err == OK else "Join failed: %s" % error_string(err)


func _refresh() -> void:
	var in_lobby: bool = NetworkManager.multiplayer.multiplayer_peer != null
	var lines := PackedStringArray()
	var ids: Array = NetworkManager.players.keys()
	ids.sort_custom(func(a, b): return NetworkManager.players[a]["slot"] < NetworkManager.players[b]["slot"])
	for id in ids:
		lines.append("%d. %s%s" % [NetworkManager.players[id]["slot"] + 1, NetworkManager.players[id]["name"], " (host)" if id == 1 else ""])
	_roster.text = "\n".join(lines)
	_name_edit.editable = not in_lobby
	_addr_edit.editable = not in_lobby
	_host_btn.visible = not in_lobby
	_join_btn.visible = not in_lobby
	_leave_btn.visible = in_lobby
	_start_btn.visible = NetworkManager.is_host()
