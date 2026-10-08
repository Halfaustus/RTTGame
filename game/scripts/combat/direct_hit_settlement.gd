class_name DirectHitSettlement
extends RefCounted

var aiming: AimingSimulation
var sample: FiringFrame
var plans: Dictionary = {}
var results: Array[Dictionary] = []
var records: Dictionary = {} # Server-only actual decisions retained for this match.
var suppression_inputs: Array[Dictionary] = [] # Prepared C inputs; no Q mutation before D.
var suppression_enabled := false
var overpenetration_enabled := false
var damage_committed: Callable # Optional match ledger; called at actual settlement time.

func begin(aim: AimingSimulation,frame: FiringFrame) -> void:
	aiming = aim
	sample = frame
	plans.clear()
	results = [] # Earlier returned step batches must not be cleared on next step.
	suppression_inputs = []

func prepare(input: Dictionary) -> Dictionary:
	if records.has(ProjectileSettlementInput.key(input)): return {"ok":false,"reason":"impact_already_committed"}
	var plan := {"ok":true,"affected_unit_ids":[]}
	if input.kind != "battlefield_exit" and not ImpactDamageRules.number(input.ammo_values.get("explosion_radius_m"),0.0):
		return {"ok":false,"reason":"impact_effect_configuration_missing"}
	if input.kind != "battlefield_exit" and float(input.ammo_values.explosion_radius_m) > 0:
		plan = ExplosionSettlement.prepare(input,aiming,sample)
		if plan.ok: plans[ProjectileSettlementInput.key(input)] = plan
		return plan
	if input.kind != "unit_impact":
		plans[ProjectileSettlementInput.key(input)] = plan
		return plan
	var unit: UnitState = aiming.units.get(input.hit_unit_id)
	if unit == null or unit.health <= 0: return {"ok":false,"reason":"impact_target_invalid"}
	var weapon: Dictionary = input.get("weapon_values",{})
	if not weapon.get("attack_top") is bool or not ImpactDamageRules.number(weapon.get("reduction_ignore"),0.0): return {"ok":false,"reason":"impact_weapon_configuration_missing"}
	var at: float = input.time_seconds
	var yaw: float = lerp_angle(sample.units[unit.unit_id].yaw,sample.units[unit.unit_id].end_yaw,sample.unit_fraction(unit.unit_id,at))
	var face := "uniform" if unit.unit_type() == UnitDefinition.UnitType.INFANTRY else ImpactDamageRules.face(vector(input.velocity),vector(input.normal),yaw,weapon.attack_top)
	var kinetic: bool = input.ammo_values.get("damage_type") == "kinetic"
	var armor: float = unit.definition.protection_kinetic if kinetic else unit.definition.protection_chemical
	if face != "uniform": armor = float((unit.definition.kinetic_armor_by_face if kinetic else unit.definition.chemical_armor_by_face).get(face,-1.0))
	var cover: Variant = aiming.inputs.get(unit.unit_id,{}).get("cover_reductions",[])
	if not cover is Array: return {"ok":false,"reason":"cover_configuration_invalid"}
	var value := ImpactDamageRules.damage(input.ammo_values,float(input.distance_m),armor,cover,float(weapon.reduction_ignore),float(input.get("penetration_loss",0.0)))
	if not value.ok: return value
	plan.merge(value,true)
	plan.affected_unit_ids = [unit.unit_id]
	plan.unit_id = unit.unit_id
	plan.face = face
	plan.member_id = 0
	if overpenetration_enabled:
		var over := KineticOverpenetration.decide(input,unit,sample,float(plan.penetration),armor)
		if not over.ok: return over
		plan.merge(over,true)
		if plan.get("continues",false): plan.damage *= KineticOverpenetration.HEALTH_FRACTION
	if unit.unit_type() == UnitDefinition.UnitType.INFANTRY:
		plan.member_id = ImpactDamageRules.nearest(unit,vector(input.point),sample.member_positions(unit.unit_id,at))
		if plan.member_id <= 0: return {"ok":false,"reason":"member_selection_invalid"}
		if suppression_enabled:
			if not ImpactDamageRules.number(input.ammo_values.get("suppression"),0.0): return {"ok":false,"reason":"suppression_configuration_missing"}
			plan.suppression_inputs = [{"unit_id":unit.unit_id,"amount":input.ammo_values.suppression,"emission_order":input.emission_order}]
	plans[ProjectileSettlementInput.key(input)] = plan
	return plan

func commit(input: Dictionary) -> Dictionary:
	if not plans.has(ProjectileSettlementInput.key(input)): return {"ok":false}
	var plan: Dictionary = plans[ProjectileSettlementInput.key(input)]
	plans.erase(ProjectileSettlementInput.key(input))
	if plan.has("effects"):
		var casualties := {}
		var batch: Array[Dictionary] = []
		for effect: Dictionary in plan.effects:
			var outcome := apply_effect(input,effect)
			if not outcome.ok: return outcome
			batch.append(outcome)
			if outcome.member_died or outcome.unit_died: casualties[effect.unit_id] = true
		suppression_inputs.append_array(plan.suppression_inputs.duplicate(true))
		records[ProjectileSettlementInput.key(input)] = {"damage_results":batch.duplicate(true),"suppression_inputs":plan.suppression_inputs.duplicate(true)}
		return {"ok":true,"casualty_unit_ids":casualties.keys()}
	if plan.affected_unit_ids.is_empty(): return {"ok":true}
	var result := apply_effect(input,plan)
	if not result.ok: return result
	if plan.has("suppression_inputs"): suppression_inputs.append_array(plan.suppression_inputs.duplicate(true))
	records[ProjectileSettlementInput.key(input)] = result.duplicate(true)
	return {"ok":true,"casualty_unit_ids":[plan.unit_id] if result.member_died or result.unit_died else []}

func apply_effect(input: Dictionary,plan: Dictionary) -> Dictionary:
	var unit: UnitState = aiming.units[plan.unit_id]
	var result: Dictionary
	if plan.member_id > 0:
		result = unit.apply_member_damage(plan.member_id,plan.damage)
	else:
		var previous := unit.health
		unit.health = maxf(0.0,previous-float(plan.damage))
		result = {"ok":true,"unit_id":unit.unit_id,"member_id":0,"health_before":previous,
			"health_after":unit.health,"damage_applied":previous-unit.health,"member_died":false,"unit_died":unit.health == 0.0}
	if not result.ok: return result
	result.merge({"emission_order":input.emission_order,"source_event_id":input.source_event_id,
		"source_unit_id":input.source_unit_id,"source_player_id":input.source_player_id,"time_seconds":input.time_seconds,
		"face":plan.face,"penetration":plan.penetration,"armor":plan.armor,"calculated_damage":plan.damage})
	if input.has("impact_sequence"):
		result.merge({"impact_sequence":input.impact_sequence,"overpenetrated":plan.get("continues",false),"exit_face":plan.get("exit_face",""),"exit_armor":plan.get("exit_armor",0.0)})
	results.append(result)
	if plan.has("distance_squared"):
		result.merge({"explosion_distance_squared":plan.distance_squared,"attenuation":plan.attenuation})
	if damage_committed.is_valid() and damage_committed.call(result.duplicate(true)) != true:
		return {"ok":false,"reason":"combat_outcome_commit_failed"}
	return result

static func vector(values: Array) -> Vector3:
	return Vector3(values[0],values[1],values[2])
