class_name WeaponSlotDefinition
extends Resource

@export var slot_id: String = "weapon"
@export var weapon: WeaponDefinition
@export var local_position := Vector3.ZERO
@export var direction_primary := false
@export var primary_weapon := false
@export var armored_primary_weapon := false
@export var orientation_priority := 1
