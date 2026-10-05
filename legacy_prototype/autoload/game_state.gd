extends Node
## Player roster derived from the lobby. Slot order == player id (pid), so every peer
## builds an identical table without extra sync. Mutable game data (space, coins...)
## is only written from server-originated events on clients.

const START_COINS := 10
const COLORS: Array[Color] = [
	Color("ff4d4d"), Color("4da6ff"), Color("ffd93d"), Color("5ddb6e"),
]

var peers: Array[int] = []        # pid -> peer id
var names: Array[String] = []     # pid -> display name
var space_of: Dictionary = {}     # pid -> board space id
var coins := PackedInt32Array()   # pid -> coins   (server-authoritative, mirrored by delta RPCs)
var stars := PackedInt32Array()   # pid -> stars


func build_from_lobby(start_space: int) -> void:
	peers.clear()
	names.clear()
	space_of.clear()
	coins.clear()
	stars.clear()
	var slots: Array = NetworkManager.players.keys()
	slots.sort_custom(func(a, b): return NetworkManager.players[a]["slot"] < NetworkManager.players[b]["slot"])
	for peer_id: int in slots:
		peers.append(peer_id)
		names.append(NetworkManager.players[peer_id]["name"])
		space_of[peers.size() - 1] = start_space
		coins.append(START_COINS)
		stars.append(0)


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


func is_bot(pid: int) -> bool:
	return peers[pid] < 0


func apply_delta(pid: int, d_coins: int, d_stars: int) -> void:
	coins[pid] += d_coins
	stars[pid] += d_stars


## Cheap order-sensitive hash of every player's inventory; the server broadcasts it
## each turn so clients can detect drift.
func stats_checksum() -> int:
	var h := 17
	for i in coins.size():
		h = (h * 31 + coins[i]) & 0x7fffffff
		h = (h * 31 + stars[i]) & 0x7fffffff
	return h


## Winner first: most stars, then most coins.
func standings() -> PackedInt32Array:
	var order: Array = range(peers.size())
	order.sort_custom(func(a, b):
		if stars[a] != stars[b]:
			return stars[a] > stars[b]
		return coins[a] > coins[b])
	return PackedInt32Array(order)
