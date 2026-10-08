class_name UnitMarkerStatus
extends RefCounted

# Server-side adapter. Future laser/transport/return-fire systems supply activity;
# absence means inactive, never a new ability or an inferred client state.
static func build(unit: UnitState, aiming: AimingSimulation, activity: Dictionary = {}) -> Dictionary:
	var disabled := not unit.runtime_weapons.is_empty()
	var engaged := false
	for weapon: RuntimeWeaponInstance in unit.runtime_weapons:
		disabled = disabled and not weapon.enabled
		if weapon.owning_node_valid() and weapon.target != null and weapon.target.valid(aiming.units): engaged = true
	var result := {"laser":activity.get("laser","inactive"),"hold_fire":disabled,
		"engaged":engaged,"return_fire_only":activity.get("return_fire_only",false),
		"carried_personnel":activity.get("carried_personnel",0),"mixed_cargo":activity.get("mixed_cargo",false),
		"fire_progress":next_fire(unit,aiming)}
	return result

static func primary_weapons(unit: UnitState) -> Array[RuntimeWeaponInstance]:
	var explicit: Array[RuntimeWeaponInstance] = []
	var largest: Array[RuntimeWeaponInstance] = []
	var maximum := -1.0
	var missing := false
	for weapon: RuntimeWeaponInstance in unit.runtime_weapons:
		var slot := weapon.slot_state()
		if slot != null and slot.definition != null and (slot.definition.primary_weapon or slot.definition.armored_primary_weapon): explicit.append(weapon)
		var caliber: float = weapon.definition.caliber_mm
		if not is_finite(caliber) or caliber <= 0:
			missing = true
			continue
		if caliber > maximum:
			maximum = caliber
			largest.clear()
		if caliber == maximum: largest.append(weapon)
	# Unknown caliber could be larger; never silently select a known secondary.
	if not explicit.is_empty(): return explicit
	if missing: return explicit # Typed empty array, including unknown caliber.
	return largest

static func next_fire(unit: UnitState, aiming: AimingSimulation) -> Dictionary:
	if unit.unit_type() not in [UnitDefinition.UnitType.INFANTRY,UnitDefinition.UnitType.ARMORED_VEHICLE] or not is_finite(unit.health) or unit.health <= 0: return {}
	var primary := primary_weapons(unit)
	var soonest := INF
	var selected := {}
	for weapon: RuntimeWeaponInstance in primary:
		if not weapon.owning_node_valid() or weapon.operable_count <= 0 or not weapon.enabled or not weapon.can_attack or weapon.target == null or not weapon.target.valid(aiming.units): continue
		var inputs: Dictionary = aiming.inputs.get(unit.unit_id,{})
		var aim_duration := weapon.sampled_aim_seconds * float(inputs.get("aim_time_multiplier",1.0))
		var loading_duration := weapon.loading_seconds() * float(inputs.get("loading_module_multiplier",1.0))
		if not weapon.definition.mechanical_loading: loading_duration *= float(inputs.get("personnel_load_multiplier",1.0))
		if not is_finite(aim_duration) or aim_duration < 0 or not is_finite(loading_duration) or loading_duration <= 0 or not is_finite(weapon.aim_progress): continue
		if weapon.fire_state.loading and not is_finite(weapon.fire_state.loading_progress): continue
		var aim_remaining := maxf(0.0,1.0-weapon.aim_progress)*aim_duration
		var loading_remaining := maxf(0.0,1.0-weapon.fire_state.loading_progress)*loading_duration if weapon.fire_state.loading else 0.0
		var remaining := maxf(aim_remaining,loading_remaining)
		# UI rule covers aim/load only. A cadence interval does not become loading.
		if remaining >= soonest: continue
		soonest = remaining
		var duration := aim_duration if aim_remaining >= loading_remaining else loading_duration
		selected = {"remaining_seconds":remaining,"progress":clampf(1.0-remaining/duration,0.0,1.0)} if remaining > 0 and duration > 0 else {}
	return selected

static func valid_activity(activity: Dictionary) -> bool:
	for key: Variant in activity:
		if key not in ["laser","return_fire_only","carried_personnel","mixed_cargo"]: return false
	if activity.get("laser","inactive") not in ["inactive","active","paused"]: return false
	if not activity.get("return_fire_only",false) is bool or not activity.get("mixed_cargo",false) is bool: return false
	var count: Variant = activity.get("carried_personnel",0)
	return count is int and count >= 0
