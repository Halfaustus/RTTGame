class_name UnitDefinition
extends Resource

enum UnitType { INFANTRY, ARMORED_VEHICLE }

@export var unit_type: UnitType = UnitType.INFANTRY
@export var hardened_speed: float = 4.0
@export var unhardened_speed: float = 4.0
@export var hardened_reverse_speed: float = 2.0
@export var unhardened_reverse_speed: float = 2.0
@export var turn_speed_degrees: float = 180.0

# Hull/legacy resource value; infantry maximum HP is member_count * 5 at runtime.
@export var maximum_health: float = 100.0
@export var weapon: WeaponDefinition

# Temporary geometry for the existing prototype assets; independent of visuals.
@export var movement_radius: float = 0.5
@export var hitbox_half_extents: Vector3 = Vector3(0.5, 0.5, 0.5)
@export var member_count: int = 8
# Minimal implementation parameters, not permanent design values.
@export var formation_spacing := 0.5
@export var member_follow_speed_multiplier := 1.25
@export var member_hitbox_half_extents := Vector3(0.15,0.4,0.15)
@export var hull_weapon_slots: Array[WeaponSlotDefinition] = []
@export var mounts: Array[WeaponMountDefinition] = []
@export var weapon_allocations: Array[WeaponAllocation] = []
@export var ability_tags: Array[String] = []
@export var member_aim_speed_degrees := 360.0
@export var protection_kinetic := -1.0 # Uniform squad protection, not directional Hull armor.
@export var protection_chemical := -1.0
@export var kinetic_armor_by_face: Dictionary = {}
@export var chemical_armor_by_face: Dictionary = {}


func spatial_valid() -> bool:
	if not weapon_allocations_valid(): return false
	var identifiers := {}
	for mount: WeaponMountDefinition in mounts:
		if mount == null or mount.mount_id.is_empty() or identifiers.has(mount.mount_id) or not is_finite(mount.initial_relative_yaw): return false
		identifiers[mount.mount_id] = true
	return is_finite(movement_radius) and movement_radius > 0.0 \
		and hitbox_half_extents.is_finite() and hitbox_half_extents.x > 0 \
		and hitbox_half_extents.y > 0 and hitbox_half_extents.z > 0 \
		and (unit_type != UnitType.INFANTRY or (member_count > 0 and is_finite(formation_spacing) and formation_spacing > 0.0 \
		and is_finite(member_follow_speed_multiplier) and member_follow_speed_multiplier >= 1.0 \
		and member_hitbox_half_extents.is_finite() and member_hitbox_half_extents.x > 0.0 \
		and member_hitbox_half_extents.y > 0.0 and member_hitbox_half_extents.z > 0.0))

func weapon_allocations_valid() -> bool:
	var occupied := {}
	var identifiers := {}
	for mount: WeaponMountDefinition in mounts:
		if mount == null: return false
		identifiers[mount.mount_id] = true
	for allocation: WeaponAllocation in weapon_allocations:
		if allocation == null or allocation.definition == null: return false
		for count: Variant in allocation.initial_inventory.values():
			if not count is int or count < 0: return false
		if allocation.initial_pending < 0: return false
		if allocation.node_kind == WeaponAllocation.NodeKind.UNASSIGNED_SQUAD_STOCK: continue
		if allocation.slot_id.is_empty(): return false
		if allocation.node_kind == WeaponAllocation.NodeKind.SOLDIER and (unit_type != UnitType.INFANTRY or allocation.member_id < 1 or allocation.member_id > member_count): return false
		if allocation.node_kind == WeaponAllocation.NodeKind.MOUNT and not identifiers.has(allocation.mount_id): return false
		var node_id := str(allocation.member_id) if allocation.node_kind == WeaponAllocation.NodeKind.SOLDIER else allocation.mount_id
		var slots: Array[String] = allocation.occupied_slots if not allocation.occupied_slots.is_empty() else [allocation.slot_id]
		for slot_id: String in slots:
			var key := "%s/%s/%s" % [allocation.node_kind,node_id,slot_id]
			if occupied.has(key): return false
			occupied[key] = true
	return true


func speed_on(hardened: bool) -> float:
	# Infantry has one speed, even if its unused hardened-speed field differs.
	return hardened_speed if hardened and unit_type == UnitType.ARMORED_VEHICLE else unhardened_speed

func is_armed() -> bool:
	if weapon != null: return true
	for allocation: WeaponAllocation in weapon_allocations:
		if allocation.definition != null and allocation.node_kind != WeaponAllocation.NodeKind.UNASSIGNED_SQUAD_STOCK: return true
	for slot: WeaponSlotDefinition in hull_weapon_slots:
		if slot.weapon != null: return true
	for mount: WeaponMountDefinition in mounts:
		for slot: WeaponSlotDefinition in mount.weapon_slots:
			if slot.weapon != null: return true
	return false
