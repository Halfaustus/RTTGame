class_name VehicleModuleRuntime
extends RefCounted

# Authorized policy: independent server stream, uniform among non-heavy modules.
var random := RandomNumberGenerator.new()
var base_inputs: Dictionary = {}
var states: Dictionary = {}
var plans: Dictionary = {}
var failure_reason := ""

func _init() -> void: random.randomize()

func begin(aiming: AimingSimulation) -> void:
	for unit: UnitState in aiming.units.values():
		if unit.unit_type() != UnitDefinition.UnitType.ARMORED_VEHICLE or states.has(unit.unit_id): continue
		unit.vehicle_modules = VehicleModuleState.new()
		states[unit.unit_id] = unit.vehicle_modules
		base_inputs[unit.unit_id] = {}
		for key: String in ["aim_time_multiplier","personnel_load_multiplier","loading_module_multiplier","spread_multiplier"]:
			base_inputs[unit.unit_id][key] = aiming.inputs.get(unit.unit_id,{}).get(key,1.0)
		apply_modifiers(unit,aiming)

func prepare(input: Dictionary,damage_plan: Dictionary) -> bool:
	var batch: Array[Dictionary] = []
	var effects: Array = damage_plan.get("effects",[damage_plan] if damage_plan.has("unit_id") else [])
	for effect: Dictionary in effects:
		if not states.has(effect.unit_id): continue
		var eligibility := VehicleModuleState.eligible(input.ammo_values,effect.penetration,effect.armor)
		if not eligibility.ok:
			failure_reason = eligibility.reason
			return false
		if not eligibility.eligible: continue
		var state: VehicleModuleState = states[effect.unit_id]
		var choose := func(ids: Array[int]): return ids[random.randi_range(0,ids.size()-1)]
		var plan := state.prepare(input.source_event_id+":"+str(effect.unit_id),eligibility.amount,choose)
		if not plan.ok:
			failure_reason = plan.reason
			return false
		plan.unit_id = effect.unit_id
		plan.source_event_id = input.source_event_id
		plan.time_seconds = input.time_seconds
		batch.append(plan)
	plans[ProjectileSettlementInput.key(input)] = batch
	return true

func commit(input: Dictionary,aiming: AimingSimulation) -> Dictionary:
	var result: Array[Dictionary] = []
	for plan: Dictionary in plans.get(ProjectileSettlementInput.key(input),[]):
		var state: VehicleModuleState = states[plan.unit_id]
		if not state.commit(plan): return {"ok":false,"reason":"module_commit_conflict"}
		apply_modifiers(aiming.units[plan.unit_id],aiming)
		result.append(plan.duplicate(true))
	plans.erase(ProjectileSettlementInput.key(input))
	return {"ok":true,"results":result}

func apply_modifiers(unit: UnitState,aiming: AimingSimulation) -> void:
	var modifiers := unit.vehicle_modules.modifiers()
	var inputs: Dictionary = aiming.inputs.get(unit.unit_id,{}).duplicate(true)
	for key: String in base_inputs[unit.unit_id]: inputs[key] = base_inputs[unit.unit_id][key]*modifiers[key]
	aiming.inputs[unit.unit_id] = inputs
	unit.personnel_speed_multiplier = modifiers.movement
	unit.personnel_vision_multiplier = modifiers.vision

func repair_level_completed(id: int,module: int,aiming: AimingSimulation) -> bool:
	# Call only at a simulation boundary; future services must coordinate any
	# within-step completion with the same resampling contract as impacts.
	if not states.has(id) or not states[id].repair_level_completed(module): return false
	apply_modifiers(aiming.units[id],aiming)
	return true
