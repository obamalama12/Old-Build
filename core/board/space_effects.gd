class_name SpaceEffects
extends RefCounted
## Pure, server-side rules for what a space does. Returns change records
## {pid, dc, ds, msg}; TurnManager applies and replicates them. To add a space type or
## event, extend this file only.

const BLUE_COINS := 3
const RED_COINS := 3
const STAR_COST := 20
const EVENT_COUNT := 4


static func change(pid: int, d_coins: int, d_stars: int, msg: String) -> Dictionary:
	return {"pid": pid, "dc": d_coins, "ds": d_stars, "msg": msg}


static func star_purchase(pid: int) -> Dictionary:
	return change(pid, -STAR_COST, 1, "%s bought a star!" % GameState.name_of(pid))


static func resolve(type: BoardSpace.Type, pid: int, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var who := GameState.name_of(pid)
	var out: Array[Dictionary] = []
	match type:
		BoardSpace.Type.BLUE:
			out.append(change(pid, BLUE_COINS, 0, "%s gains %d coins" % [who, BLUE_COINS]))
		BoardSpace.Type.RED:
			out.append(change(pid, -RED_COINS, 0, "%s loses %d coins" % [who, RED_COINS]))
		BoardSpace.Type.EVENT:
			out.append_array(_event(pid, rng))
	return out


static func _event(pid: int, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var who := GameState.name_of(pid)
	var out: Array[Dictionary] = []
	var others: Array[int] = []
	for p in GameState.count():
		if p != pid and GameState.is_connected_pid(p):
			others.append(p)
	var pick := rng.randi() % EVENT_COUNT
	if pick == 3 and others.is_empty():
		pick = 0
	match pick:
		0:
			out.append(change(pid, 10, 0, "Coin shower! %s gets 10 coins" % who))
		1:
			out.append(change(pid, -5, 0, "Pickpocket! %s loses 5 coins" % who))
		2:
			for p in GameState.count():
				if GameState.is_connected_pid(p):
					out.append(change(p, 3, 0, "Party time! %s gets 3 coins" % GameState.name_of(p)))
		3:
			var other: int = others[rng.randi() % others.size()]
			var diff := GameState.coins[other] - GameState.coins[pid]
			out.append(change(pid, diff, 0, "%s swaps coins with %s!" % [who, GameState.name_of(other)]))
			out.append(change(other, -diff, 0, ""))
	return out
