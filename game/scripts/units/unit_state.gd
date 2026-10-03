class_name UnitState
extends RefCounted

var unit_id: int
var owner_peer_id: int
var position: Vector3


func _init(id: int, owner: int, initial_position: Vector3) -> void:
	unit_id = id
	owner_peer_id = owner
	position = initial_position
