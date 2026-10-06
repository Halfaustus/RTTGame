class_name UnitDefinition
extends Resource

enum UnitType { INFANTRY, ARMORED_VEHICLE }

@export var unit_type: UnitType = UnitType.INFANTRY
@export var configuration_source: String = "unconfigured"
# Generic isolated-test defaults; active presets configure movement explicitly.
@export var hardened_speed: float = 4.0
@export var unhardened_speed: float = 4.0
@export var hardened_reverse_speed: float = 2.0
@export var unhardened_reverse_speed: float = 2.0
@export var turn_speed_degrees: float = 360.0

# Hull/legacy resource value; infantry maximum HP is member_count * 5 at runtime.
@export var maximum_health: float = 10.0
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
		if mount.kind not in [WeaponMountDefinition.Kind.MAIN_TURRET, WeaponMountDefinition.Kind.WEAPON_STATION]: return false
		identifiers[mount.mount_id] = true
	return is_finite(movement_radius) and movement_radius > 0.0 \
		and hitbox_half_extents.is_finite() and hitbox_half_extents.x > 0 \
		and hitbox_half_extents.y > 0 and hitbox_half_extents.z > 0 \
		and (unit_type != UnitType.INFANTRY or (member_count > 0 and is_finite(formation_spacing) and formation_spacing > 0.0 \
		and is_finite(member_follow_speed_multiplier) and member_follow_speed_multiplier >= 1.0 \
		and member_hitbox_half_extents.is_finite() and member_hitbox_half_extents.x > 0.0 \
		and member_hitbox_half_extents.y > 0.0 and member_hitbox_half_extents.z > 0.0))

func weapon_allocations_valid() -> bool:
	var models := {}
	var quantities := {}
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
		if allocation.node_kind == WeaponAllocation.NodeKind.SOLDIER:
			var model := allocation.definition.definition_id
			if model.is_empty(): return false
			if models.has(model) and models[model] != allocation.definition: return false
			models[model] = allocation.definition
			quantities[model] = int(quantities.get(model,0))+1
			if allocation.definition.maximum_squad_count > 0 and quantities[model] > allocation.definition.maximum_squad_count: return false
		if allocation.node_kind == WeaponAllocation.NodeKind.MOUNT and not identifiers.has(allocation.mount_id): return false
	return installation_issues().is_empty()

# Sole occupancy authority for slot weapons AND allocations; Hull is normalized
# to runtime "hull". Tuple keys avoid delimiter ambiguity. Empty declared slots
# do not equip weapons. Reserving other slots cannot conceal the actual slot.
func installation_issues() -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	var occupied := {}
	var mount_ids := {}
	for i: int in hull_weapon_slots.size():
		_reserve_slot(hull_weapon_slots[i],WeaponAllocation.NodeKind.HULL,"hull","hull_weapon_slots[%d]" % i,occupied,issues)
	for i: int in mounts.size():
		var mount := mounts[i]
		var path := "mounts[%d]" % i
		if mount == null or mount.mount_id.is_empty() or mount_ids.has(mount.mount_id):
			issues.append({"code":"invalid_mount_reference","path":path+".mount_id","message":"Mount ID must be nonempty and unique"})
			continue
		mount_ids[mount.mount_id] = true
		for j: int in mount.weapon_slots.size():
			_reserve_slot(mount.weapon_slots[j],WeaponAllocation.NodeKind.MOUNT,mount.mount_id,path+".weapon_slots[%d]" % j,occupied,issues)
	for i: int in weapon_allocations.size():
		var allocation := weapon_allocations[i]
		var path := "weapon_allocations[%d]" % i
		if allocation == null:
			issues.append({"code":"missing_allocation","path":path,"message":"Allocation is null"})
			continue
		if allocation.node_kind == WeaponAllocation.NodeKind.UNASSIGNED_SQUAD_STOCK: continue
		if allocation.node_kind not in [WeaponAllocation.NodeKind.SOLDIER,WeaponAllocation.NodeKind.HULL,WeaponAllocation.NodeKind.MOUNT]:
			issues.append({"code":"invalid_node_kind","path":path+".node_kind","message":"Unknown installation node"})
			continue
		var node_id := str(allocation.member_id) if allocation.node_kind == WeaponAllocation.NodeKind.SOLDIER else ("hull" if allocation.node_kind == WeaponAllocation.NodeKind.HULL else allocation.mount_id)
		if allocation.node_kind == WeaponAllocation.NodeKind.MOUNT and not mount_ids.has(node_id):
			issues.append({"code":"missing_mount","path":path+".mount_id","message":"Allocation references an absent mount"})
		var slots: Array[String] = []
		slots.assign(allocation.occupied_slots if not allocation.occupied_slots.is_empty() else [allocation.slot_id])
		if not slots.has(allocation.slot_id): slots.append(allocation.slot_id)
		for slot_id: String in slots:
			_reserve_installation(allocation.node_kind,node_id,slot_id,path,occupied,issues)
	return issues

func _reserve_slot(slot: WeaponSlotDefinition,kind: int,node_id: String,path: String,occupied: Dictionary,issues: Array[Dictionary]) -> void:
	if slot == null:
		issues.append({"code":"missing_slot","path":path,"message":"Slot is null"})
	elif slot.weapon != null:
		_reserve_installation(kind,node_id,slot.slot_id,path,occupied,issues)

func _reserve_installation(kind: int,node_id: String,slot_id: String,path: String,occupied: Dictionary,issues: Array[Dictionary]) -> void:
	if slot_id.is_empty():
		issues.append({"code":"missing_slot_id","path":path+".slot_id","message":"Equipped slot ID is empty"})
		return
	var key := JSON.stringify([kind,node_id,slot_id])
	if occupied.has(key):
		issues.append({"code":"installation_collision","path":path,"related_path":occupied[key],"installation":[kind,node_id,slot_id],"message":"Two weapons occupy the same installation"})
	else:
		occupied[key] = path


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
