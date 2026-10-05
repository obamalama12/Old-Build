extends Node
## Local-only signals so UI/VFX never reach into game logic. Emitted on every peer
## after the server's authoritative event arrives.

signal turn_started(pid: int)
signal dice_rolled(pid: int, value: int)
signal pawn_moved(pid: int, space_id: int)
