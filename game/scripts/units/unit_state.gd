class_name UnitState
extends RefCounted

var unit_id: int
var owner_peer_id: int
var owner_player_id: int = 0
var position: Vector3
var yaw: float = 0.0
var team_id: int = 1
var _maximum_health := 100.0
var _health := 100.0
var maximum_health: float:
	get: return members.size() * SoldierState.MAXIMUM_HEALTH if not members.is_empty() else _maximum_health
	set(value): _maximum_health = value
var health: float:
	get:
		if members.is_empty(): return _health
		var total := 0.0
		for member: SoldierState in members: total += member.health
		return total
	set(value):
		if members.is_empty():
			_health = value
			return
		# Compatibility setter for old test/setup interfaces, not damage adjudication.
		var remaining := clampf(value,0.0,maximum_health)
		for member: SoldierState in members:
			member.health = minf(SoldierState.MAXIMUM_HEALTH,remaining)
			remaining -= member.health
var generated_tick: int = -1
var weapon: WeaponDefinition
var definition: UnitDefinition
var members: Array[SoldierState] = []
var formation_slots := PackedVector3Array()
var mounts: Array[WeaponMountState] = []
var hull_weapon_slots: Array[WeaponSlotDefinition] = []
var runtime_slots: Array[WeaponSlotState] = []
var runtime_weapons: Array[RuntimeWeaponInstance] = []
var unassigned_inventory: Dictionary = {}
var _formation_members: Array[int] = []
var profile: Dictionary = {}
var member_health: PackedFloat32Array:
	get:
		var result := PackedFloat32Array()
		for member: SoldierState in members: result.append(member.health)
		return result
var member_offsets: PackedVector3Array:
	get: return formation_slots.duplicate()


func configure(team: int, unit_definition: UnitDefinition) -> void:
	definition = unit_definition
	team_id = team
	members.clear()
	mounts.clear()
	runtime_slots.clear()
	runtime_weapons.clear()
	unassigned_inventory.clear()
	hull_weapon_slots.clear()
	_formation_members.clear()
	formation_slots.clear()
	maximum_health = definition.maximum_health
	health = maximum_health
	weapon = definition.weapon
	if unit_type() == UnitDefinition.UnitType.INFANTRY:
		for index: int in definition.member_count:
			var member := SoldierState.new()
			member.member_id = index + 1
			member.hitbox_half_extents = definition.member_hitbox_half_extents
			members.append(member)
	else:
		hull_weapon_slots.assign(definition.hull_weapon_slots)
		for mount_definition: WeaponMountDefinition in definition.mounts:
			var mount := WeaponMountState.new()
			mount.mount_id = mount_definition.mount_id
			mount.kind = mount_definition.kind
			mount.hull = weakref(self)
			mount.rotation_speed_degrees = mount_definition.rotation_speed_degrees
			mount.world_yaw = wrapf(yaw+mount_definition.initial_relative_yaw,-PI,PI)
			mount.weapon_slots.assign(mount_definition.weapon_slots)
			mounts.append(mount)
	initialize_spatial()
	_initialize_weapons()


func _initialize_weapons() -> void:
	# Existing explicitly configured slots also use the same runtime representation.
	for slot_definition: WeaponSlotDefinition in hull_weapon_slots:
		if slot_definition.weapon != null: _attach_weapon(slot_definition,WeaponAllocation.NodeKind.HULL,"hull",self)
	for mount: WeaponMountState in mounts:
		for slot_definition: WeaponSlotDefinition in mount.weapon_slots:
			if slot_definition.weapon != null: _attach_weapon(slot_definition,WeaponAllocation.NodeKind.MOUNT,mount.mount_id,mount)
	for allocation: WeaponAllocation in definition.weapon_allocations:
		if allocation.node_kind == WeaponAllocation.NodeKind.UNASSIGNED_SQUAD_STOCK:
			for ammo_id: String in allocation.initial_inventory:
				unassigned_inventory[ammo_id] = unassigned_inventory.get(ammo_id,0) + allocation.initial_inventory[ammo_id]
			continue
		var spatial: RefCounted = self
		var identifier := "hull"
		if allocation.node_kind == WeaponAllocation.NodeKind.SOLDIER:
			if allocation.member_id < 1 or allocation.member_id > members.size(): continue
			spatial = members[allocation.member_id-1]
			identifier = str(allocation.member_id)
		elif allocation.node_kind == WeaponAllocation.NodeKind.MOUNT:
			spatial = null
			for mount: WeaponMountState in mounts:
				if mount.mount_id == allocation.mount_id: spatial = mount
			identifier = allocation.mount_id
		if spatial == null or allocation.definition == null: continue
		var slot_definition := WeaponSlotDefinition.new()
		slot_definition.slot_id = allocation.slot_id
		slot_definition.weapon = allocation.definition
		slot_definition.direction_primary = allocation.direction_primary
		slot_definition.orientation_priority = allocation.orientation_priority
		var instance := _attach_weapon(slot_definition,allocation.node_kind,identifier,spatial)
		instance.inventory = allocation.initial_inventory.duplicate(true)
		instance.initialize_first_magazine()
		if spatial is SoldierState: spatial.weapon_slots.append(slot_definition)
		elif spatial is WeaponMountState: spatial.weapon_slots.append(slot_definition)
		else: hull_weapon_slots.append(slot_definition)

func _attach_weapon(slot_definition: WeaponSlotDefinition, kind: int, identifier: String, spatial: RefCounted) -> RuntimeWeaponInstance:
	var slot_state := WeaponSlotState.new(slot_definition,kind,identifier)
	var instance := RuntimeWeaponInstance.new(self,slot_state,spatial)
	slot_state.runtime_weapon = instance
	runtime_slots.append(slot_state)
	runtime_weapons.append(instance)
	return instance


func initialize_spatial() -> void:
	_reassign_formation()
	for member: SoldierState in members:
		member.aim_yaw = yaw
		if member.formation_slot >= 0:
			member.position = position + formation_slots[member.formation_slot].rotated(Vector3.UP,yaw)
	for index: int in mounts.size():
		mounts[index].world_yaw = wrapf(yaw+definition.mounts[index].initial_relative_yaw,-PI,PI)


func _reassign_formation() -> void:
	if not profile.is_empty(): profile["formation_checks"] = profile.get("formation_checks",0) + 1
	var alive: Array[int] = []
	for member: SoldierState in members:
		if member.health > 0: alive.append(member.member_id)
	if alive == _formation_members: return
	if not profile.is_empty(): profile["formation_generations"] = profile.get("formation_generations",0) + 1
	_formation_members = alive
	formation_slots = SquadFormation.slots(alive.size(),definition.formation_spacing)
	var index := 0
	for member: SoldierState in members:
		member.formation_slot = index if member.health > 0 else -1
		if not profile.is_empty(): profile["slot_assignments"] = profile.get("slot_assignments",0) + 1
		if member.health > 0: index += 1


func advance_members(delta: float) -> bool:
	_reassign_formation()
	var changed := false
	for member: SoldierState in members:
		if member.formation_slot < 0: continue
		if not profile.is_empty(): profile["soldier_follow_updates"] = profile.get("soldier_follow_updates",0) + 1
		var target := position + formation_slots[member.formation_slot].rotated(Vector3.UP,yaw)
		var next := member.position.move_toward(target,definition.unhardened_speed * definition.member_follow_speed_multiplier * delta)
		changed = changed or next != member.position
		member.position = next
	return changed


func apply_prototype_damage(amount: float) -> void:
	if members.is_empty():
		health = maxf(0.0,health-amount)
		return
	# Minimal old-combat adapter: one living member, no excess damage spill.
	for member: SoldierState in members:
		if member.health > 0:
			member.health = maxf(0.0,member.health-amount)
			break
	_reassign_formation()


func structure_snapshot() -> Dictionary:
	if not profile.is_empty(): profile["internal_state_serializations"] = profile.get("internal_state_serializations",0) + 1
	var people: Array[Dictionary] = []
	for member: SoldierState in members: people.append(member.snapshot())
	var attachments: Array[Dictionary] = []
	for mount: WeaponMountState in mounts: attachments.append(mount.snapshot(yaw))
	var armament: Array[Dictionary] = []
	for instance: RuntimeWeaponInstance in runtime_weapons: armament.append(instance.snapshot())
	return {"schema_version":1,"unit_id":unit_id,"members":people,"mounts":attachments,"weapons":armament}


# Query actual member positions directly; the legacy squad box is not a filter.
func hit_members(start: Vector3, end: Vector3) -> Array[int]:
	var result: Array[int] = []
	for member: SoldierState in members:
		if member.intersects_hit_segment(start,end): result.append(member.member_id)
	return result


func slot_world_yaw(mount_id: String = "") -> float:
	if mount_id.is_empty(): return yaw
	for mount: WeaponMountState in mounts:
		if mount.mount_id == mount_id: return mount.world_yaw
	return NAN


func blocks_movement() -> bool:
	return health > 0.0 and unit_type() == UnitDefinition.UnitType.ARMORED_VEHICLE


func movement_radius() -> float:
	return definition.movement_radius if definition != null else 0.5


func hitbox_extents() -> Vector3:
	return definition.hitbox_half_extents if definition != null else Vector3.ONE * 0.5


# Server-space oriented box query for future projectiles; does not deal damage.
func intersects_hit_segment(start: Vector3, end: Vector3) -> bool:
	if health <= 0 or not is_finite(yaw) or not start.is_finite() or not end.is_finite(): return false
	if definition != null and not definition.spatial_valid(): return false
	var local_start := (start - position).rotated(Vector3.UP, -yaw)
	var direction := (end - start).rotated(Vector3.UP, -yaw)
	var extents := hitbox_extents()
	var first := 0.0
	var last := 1.0
	for axis: int in 3:
		if is_zero_approx(direction[axis]):
			if absf(local_start[axis]) > extents[axis]: return false
		else:
			var a := (-extents[axis] - local_start[axis]) / direction[axis]
			var b := (extents[axis] - local_start[axis]) / direction[axis]
			first = maxf(first, minf(a,b))
			last = minf(last, maxf(a,b))
			if first > last: return false
	return true


# Compatibility entry for old setup callers; member HP remains authoritative.
func synchronize_legacy_members() -> void:
	_reassign_formation()


func armor_direction(source: Vector3) -> String:
	if not source.is_finite() or not is_finite(yaw): return "unknown"
	var incoming := Vector2(source.x - position.x, source.z - position.z)
	if incoming.is_zero_approx(): return "unknown"
	var forward := Vector2(-sin(yaw), -cos(yaw))
	var angle := absf(forward.angle_to(incoming))
	if angle <= deg_to_rad(60.0) + 0.000001: return "front"
	if angle >= deg_to_rad(135.0) - 0.000001: return "rear"
	return "side"


func snapshot() -> Dictionary:
	return {"unit_id": unit_id, "owner_peer_id": owner_peer_id, "owner_player_id": owner_player_id, "team_id": team_id,
		"position": position, "yaw": yaw, "maximum_health": maximum_health, "health": health, "unit_type": unit_type(), "armed": is_armed()}

func is_armed() -> bool: return weapon != null or not runtime_weapons.is_empty()

func weapon_summary() -> Array[Dictionary]:
	var grouped := {}
	for instance: RuntimeWeaponInstance in runtime_weapons:
		var id := instance.definition.definition_id
		if not grouped.has(id): grouped[id] = {"definition_id":id,"count":0,"ammunition":{}}
		grouped[id].count += 1
		for ammo_id: String in instance.inventory:
			grouped[id].ammunition[ammo_id] = grouped[id].ammunition.get(ammo_id,0)+instance.inventory[ammo_id]
	var result: Array[Dictionary] = []
	for value: Dictionary in grouped.values(): result.append(value)
	return result

func unassigned_weapon_stock() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for allocation: WeaponAllocation in definition.weapon_allocations:
		if allocation.node_kind == WeaponAllocation.NodeKind.UNASSIGNED_SQUAD_STOCK:
			result.append({"definition_id":allocation.definition.definition_id,"count":null,"assignment_pending":true,"ammunition":unassigned_inventory.duplicate()})
	return result


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
