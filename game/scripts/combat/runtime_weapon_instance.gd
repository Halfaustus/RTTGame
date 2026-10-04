class_name RuntimeWeaponInstance
extends RefCounted

var instance_id: String
var definition: WeaponDefinition
var slot: WeakRef
var owner: WeakRef
var node: WeakRef
var node_kind: int
var node_id: String
var enabled := true
var manual_target := true
var target: AttackTarget
var inventory: Dictionary = {}
var pending_rounds := 0
var eligibility_reason := "no_target"
var can_attack := false
var desired_yaw := 0.0
var desired_direction := Vector3.ZERO
var aim_progress := 0.0
var sampled_aim_seconds := -1.0
var aim_timer_complete := false
var orientation_ready := false
var is_aimed := false
var fire_state := WeaponFireState.new()

func _init(state: UnitState, owning_slot: WeaponSlotState, spatial_node: RefCounted) -> void:
	owner = weakref(state)
	slot = weakref(owning_slot)
	node = weakref(spatial_node)
	node_kind = owning_slot.node_kind
	node_id = owning_slot.node_id
	definition = owning_slot.definition.weapon
	instance_id = "%s/%s/%s/%s" % [state.unit_id,node_kind,node_id,owning_slot.definition.slot_id]

func owner_state() -> UnitState: return owner.get_ref()

func initialize_first_magazine() -> void:
	# Inventory is TOTAL available ammunition, including ready rounds (DB22).
	# Readiness never transfers or adds stock; ammo is selected only at firing.
	pending_rounds = 0
	for ammo: AmmoDefinition in definition.ammo_definitions:
		var available: int = maxi(0,int(inventory.get(ammo.ammo_id,0)))
		pending_rounds += available
		if pending_rounds >= definition.capacity:
			pending_rounds = definition.capacity
			return

func spatial_node() -> RefCounted: return node.get_ref()
func slot_state() -> WeaponSlotState: return slot.get_ref()

func owning_node_valid() -> bool:
	var state := owner_state()
	var value := spatial_node()
	if state == null or value == null or slot_state() == null or state.health <= 0.0: return false
	if not state.runtime_weapons.has(self): return false
	if node_kind == WeaponAllocation.NodeKind.SOLDIER: return state.members.has(value) and value.health > 0.0
	if node_kind == WeaponAllocation.NodeKind.MOUNT: return state.mounts.has(value)
	return value == state

func world_yaw() -> float:
	var value := spatial_node()
	if node_kind == WeaponAllocation.NodeKind.SOLDIER: return value.aim_yaw
	if node_kind == WeaponAllocation.NodeKind.MOUNT: return value.world_yaw
	return owner_state().yaw

func world_position() -> Vector3:
	var origin: Vector3 = spatial_node().position if node_kind == WeaponAllocation.NodeKind.SOLDIER else owner_state().position
	return origin + slot_state().definition.local_position.rotated(Vector3.UP,world_yaw())

func bind_target(value: AttackTarget, manual: bool = true) -> void:
	if target == null or not target.same(value): reset_aim()
	target = value
	manual_target = manual
	can_attack = false
	is_aimed = false
	orientation_ready = false

func reset_aim() -> void:
	aim_progress = 0.0
	sampled_aim_seconds = -1.0
	aim_timer_complete = false
	orientation_ready = false
	is_aimed = false

func clear_target() -> void:
	target = null
	can_attack = false
	eligibility_reason = "no_target"
	reset_aim()

func has_ammunition() -> bool:
	for ammo: AmmoDefinition in definition.ammo_definitions:
		if int(inventory.get(ammo.ammo_id,0)) >= definition.consumption_per_projectile: return true
	return false

func snapshot() -> Dictionary:
	var result := {"instance_id":instance_id,"definition_id":definition.definition_id,"node_kind":node_kind,"node_id":node_id,
		"target_id":target.unit_id if target != null else 0,"can_attack":can_attack,"reason":eligibility_reason,
		"desired_yaw":desired_yaw,"aim_progress":aim_progress,"sampled_aim_seconds":sampled_aim_seconds,
		"aim_timer_complete":aim_timer_complete,"orientation_ready":orientation_ready,"is_aimed":is_aimed,
		"actual_yaw":world_yaw() if spatial_node() != null and owner_state() != null else 0.0}
	result["fire"] = fire_state.snapshot()
	result["inventory"] = inventory.duplicate()
	result["pending_rounds"] = pending_rounds
	return result

func observation() -> Dictionary:
	var result := snapshot()
	result["owner_unit_id"] = owner_state().unit_id if owner_state() != null else 0
	result["slot_id"] = slot_state().definition.slot_id if slot_state() != null else ""
	result["range_m"] = definition.range_m
	result["temporary_fields"] = definition.temporary_fields.duplicate()
	result["inventory"] = inventory.duplicate()
	result["pending_rounds"] = pending_rounds
	if owning_node_valid():
		result["weapon_position"] = world_position()
		if target != null and target.state() != null: result["target_distance_m"] = world_position().distance_to(target.position())
	return result
