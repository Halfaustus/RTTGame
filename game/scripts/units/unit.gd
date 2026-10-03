extends Node3D

var unit_id: int = 0
var owner_peer_id: int = 0


func setup(new_unit_id: int, new_owner_peer_id: int) -> void:
	unit_id = new_unit_id
	owner_peer_id = new_owner_peer_id

	print(
		"Unit %d initialized. Owner peer: %d"
		% [unit_id, owner_peer_id]
	)
