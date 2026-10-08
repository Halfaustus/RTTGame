class_name WeaponAllocation
extends Resource

enum NodeKind { SOLDIER, HULL, MOUNT, UNASSIGNED_SQUAD_STOCK }
@export var definition: WeaponDefinition
@export var node_kind: NodeKind = NodeKind.SOLDIER
@export var member_id: int = 0
@export var mount_id: String = ""
@export var slot_id: String = "primary"
@export var occupied_slots: Array[String] = []
@export var initial_inventory: Dictionary = {}
@export var initial_pending: int = 0
@export var direction_primary: bool = false
@export var primary_weapon := false # Server-only marker selection, not orientation priority.
@export var armored_primary_weapon := false # Server-only marker selection, not orientation priority.
@export var orientation_priority := 1
@export var retention_priority := -1 # Unit configuration; missing blocks reassignment.
# Unassigned squad stock creates NO weapon instance or implied launcher count.
