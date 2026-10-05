extends Node
## Local-only signals so UI/VFX never reach into game logic. Emitted on every peer
## after the server's authoritative event arrives.

signal turn_started(pid: int, round_no: int, max_rounds: int)
signal dice_rolled(pid: int, value: int)
signal pawn_moved(pid: int, space_id: int)
signal branch_prompt(pid: int, options: PackedInt32Array)
signal game_over
