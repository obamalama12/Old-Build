extends BoardGraph
## Placeholder board: 16-space ring with a 2-space shortcut branching at 3 and rejoining at 8.

const RING := 16
const RADIUS := 9.0


func _build() -> void:
	start_id = 0
	for i in RING:
		var a := TAU * i / RING
		var type := BoardSpace.Type.BLUE
		if i == 0:
			type = BoardSpace.Type.START
		elif i == 8:
			type = BoardSpace.Type.STAR
		elif i % 4 == 3:
			type = BoardSpace.Type.RED
		elif i % 5 == 2:
			type = BoardSpace.Type.EVENT
		var next: Array[int] = [(i + 1) % RING]
		if i == 3:
			next.append(16)  # branch into the shortcut
		add_space(i, Vector3(cos(a) * RADIUS, 0, sin(a) * RADIUS), type, next)
	add_space(16, Vector3(1.5, 0, 4.5), BoardSpace.Type.EVENT, [17])
	add_space(17, Vector3(-4.5, 0, 2.0), BoardSpace.Type.BLUE, [8])
