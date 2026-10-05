extends Node
## Player roster derived from the lobby. Slot order == player id (pid), so every peer
## builds an identical table without extra sync. Mutable game data (space, coins...)
## is only written from server-originated events on clients.

const COLORS: Array[Color] = [
	Color("ff4d4d"), Color("4da6ff"), Color("ffd93d"), Color("5ddb6e"),
]

var peers: Array[int] = []        # pid -> peer id
var names: Array[String] = []     # pid -> display name
var space_of: Dictionary = {}     # pid -> board space id


func build_from_lobby(start_space: int) -> void:
	peers.clear()
	names.clear()
	space_of.clear()
	var slots: Array = NetworkManager.players.keys()
	slots.sort_custom(func(a, b): return NetworkManager.players[a]["slot"] < NetworkManager.players[b]["slot"])
	for peer_id: int in slots:
		peers.append(peer_id)
		names.append(NetworkManager.players[peer_id]["name"])
		space_of[peers.size() - 1] = start_space


func count() -> int:
	return peers.size()


func peer_of(pid: int) -> int:
	return peers[pid]


func pid_of(peer_id: int) -> int:
	return peers.find(peer_id)


func name_of(pid: int) -> String:
	return names[pid]


func color_of(pid: int) -> Color:
	return COLORS[pid % COLORS.size()]


func is_connected_pid(pid: int) -> bool:
	var info: Dictionary = NetworkManager.players.get(peers[pid], {})
	return info.get("connected", false)
