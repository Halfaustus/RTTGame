class_name WeaponSlotState
extends RefCounted

var definition: WeaponSlotDefinition
var node_kind: int
var node_id: String
var runtime_weapon: RuntimeWeaponInstance

func _init(slot: WeaponSlotDefinition, kind: int, id: String) -> void:
	definition = slot
	node_kind = kind
	node_id = id
