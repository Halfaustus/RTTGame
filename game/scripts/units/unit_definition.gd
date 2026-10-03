class_name UnitDefinition
extends Resource

enum UnitType { INFANTRY, ARMORED_VEHICLE }

@export var unit_type: UnitType = UnitType.INFANTRY
@export var hardened_speed: float = 4.0
@export var unhardened_speed: float = 4.0
@export var hardened_reverse_speed: float = 2.0
@export var unhardened_reverse_speed: float = 2.0
@export var turn_speed_degrees: float = 180.0

@export var maximum_health: float = 100.0
@export var weapon: WeaponDefinition


func speed_on(hardened: bool) -> float:
	# Infantry has one speed, even if its unused hardened-speed field differs.
	return hardened_speed if hardened and unit_type == UnitType.ARMORED_VEHICLE else unhardened_speed
