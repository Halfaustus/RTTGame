class_name UnitState
extends RefCounted

var unit_id: int
var owner_peer_id: int
var owner_player_id: int = 0
var position: Vector3
var yaw: float = 0.0
var team_id: int = 1
var maximum_health: float = 100.0
var health: float = 100.0
var weapon: WeaponDefinition
var definition: UnitDefinition


func configure(team: int, unit_definition: UnitDefinition) -> void:
	definition = unit_definition
	team_id = team
	maximum_health = definition.maximum_health
	health = maximum_health
	weapon = definition.weapon


func snapshot() -> Dictionary:
	return {"unit_id": unit_id, "owner_peer_id": owner_peer_id, "owner_player_id": owner_player_id, "team_id": team_id,
		"position": position, "yaw": yaw, "maximum_health": maximum_health, "health": health, "unit_type": unit_type(), "armed": weapon != null}


func reverse_speed_on(hardened: bool) -> float:
	return definition.hardened_reverse_speed if hardened else definition.unhardened_reverse_speed


func speed_on(hardened: bool, fallback: float) -> float:
	return definition.speed_on(hardened) if definition != null else fallback


func unit_type() -> int:
	return definition.unit_type if definition != null else UnitDefinition.UnitType.INFANTRY


func _init(id: int, owner: int, initial_position: Vector3) -> void:
	unit_id = id
	owner_peer_id = owner
	position = initial_position
