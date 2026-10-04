class_name WeaponMountDefinition
extends Resource

enum Kind { MAIN_TURRET, WEAPON_STATION, OTHER }
@export var mount_id: String = "mount"
@export var kind: Kind = Kind.MAIN_TURRET
@export var initial_relative_yaw := 0.0
@export var weapon_slots: Array[WeaponSlotDefinition] = []
@export var rotation_speed_degrees := 120.0
