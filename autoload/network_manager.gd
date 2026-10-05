extends Node
## ENet host/join + lobby roster. The server (peer 1) owns the roster; clients only ask.
## The host is also a player, so it holds peer id 1 in `players`.

const PROTOCOL_VERSION := 1
const DEFAULT_PORT := 7777
const MAX_PLAYERS := 4
const MIN_PLAYERS_TO_START := 1  # raise to 2 for release; 1 allows solo testing
const MAIN_SCENE := "res://main.tscn"
const GAME_SCENE := "res://game/game.tscn"

signal lobby_changed
signal join_failed(reason: String)
signal peer_left(peer_id: int)   # server-side, fired mid-game too
signal peer_ready(peer_id: int)  # server-side, a peer finished loading the game scene

## peer_id -> {"name": String, "slot": int, "connected": bool}
var players: Dictionary = {}
var local_name := "Player"
var board_id := "meadow"
var in_game := false
var ready_peers: Dictionary = {}
var last_message := ""  # shown by the menu after being kicked back to it


func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_host() -> bool:
	return multiplayer.multiplayer_peer is ENetMultiplayerPeer and multiplayer.is_server()


func local_id() -> int:
	return multiplayer.get_unique_id()


# --- session control ----------------------------------------------------------

func host(display_name: String, port: int = DEFAULT_PORT) -> Error:
	leave(false)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	local_name = _clean_name(display_name)
	players[1] = {"name": local_name, "slot": 0, "connected": true}
	lobby_changed.emit()
	return OK


func join(address: String, display_name: String, port: int = DEFAULT_PORT) -> Error:
	leave(false)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	local_name = _clean_name(display_name)
	return OK


func leave(go_to_menu: bool = true) -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	var was_in_game := in_game
	players.clear()
	ready_peers.clear()
	in_game = false
	lobby_changed.emit()
	if go_to_menu and was_in_game:
		get_tree().change_scene_to_file(MAIN_SCENE)


func start_game() -> void:
	if not multiplayer.is_server() or in_game or players.size() < MIN_PLAYERS_TO_START:
		return
	_rpc_begin_game.rpc(board_id)


## Called by game.gd on every peer once its scene tree exists.
func notify_scene_ready() -> void:
	if multiplayer.is_server():
		_mark_ready(1)
	else:
		_rpc_peer_ready.rpc_id(1)


func all_ready() -> bool:
	for id: int in players:
		if players[id]["connected"] and not ready_peers.has(id):
			return false
	return true


# --- RPCs ---------------------------------------------------------------------

@rpc("any_peer", "reliable")
func _rpc_register(version: int, display_name: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var reason := ""
	if version != PROTOCOL_VERSION:
		reason = "Version mismatch"
	elif in_game:
		reason = "Game already started"
	elif players.size() >= MAX_PLAYERS:
		reason = "Lobby full"
	elif players.has(id):
		return
	if reason != "":
		_rpc_rejected.rpc_id(id, reason)
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	players[id] = {"name": _clean_name(display_name), "slot": _free_slot(), "connected": true}
	_broadcast_lobby()


@rpc("authority", "reliable")
func _rpc_rejected(reason: String) -> void:
	last_message = reason
	join_failed.emit(reason)


@rpc("authority", "reliable")
func _rpc_sync_lobby(roster: Dictionary) -> void:
	players = roster
	lobby_changed.emit()


@rpc("authority", "call_local", "reliable")
func _rpc_begin_game(bid: String) -> void:
	board_id = bid
	in_game = true
	ready_peers.clear()
	get_tree().change_scene_to_file(GAME_SCENE)


@rpc("any_peer", "reliable")
func _rpc_peer_ready() -> void:
	if multiplayer.is_server():
		_mark_ready(multiplayer.get_remote_sender_id())


# --- internals ----------------------------------------------------------------

func _mark_ready(id: int) -> void:
	ready_peers[id] = true
	peer_ready.emit(id)


func _broadcast_lobby() -> void:
	_rpc_sync_lobby.rpc(players)
	lobby_changed.emit()


func _free_slot() -> int:
	var used: Array = players.values().map(func(p): return p["slot"])
	for s in MAX_PLAYERS:
		if not used.has(s):
			return s
	return MAX_PLAYERS - 1


static func _clean_name(raw: String) -> String:
	var n := raw.strip_edges().substr(0, 16)
	return n if n != "" else "Player"


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server() or not players.has(id):
		return
	if in_game:
		players[id]["connected"] = false  # keep slot so pids stay stable
	else:
		players.erase(id)
	peer_left.emit(id)
	_broadcast_lobby()


func _on_connected_to_server() -> void:
	_rpc_register.rpc_id(1, PROTOCOL_VERSION, local_name)


func _on_connection_failed() -> void:
	leave(false)
	last_message = "Could not connect"
	join_failed.emit(last_message)


func _on_server_disconnected() -> void:
	last_message = "Host closed the session"
	leave(true)
	join_failed.emit(last_message)
