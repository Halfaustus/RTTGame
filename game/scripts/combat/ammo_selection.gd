class_name AmmoSelection
extends RefCounted

# Pure selection preview. No HP, suppression, module or inventory writes.
static func ground_selection(weapon: RuntimeWeaponInstance) -> Dictionary:
	return ground_selection_values(weapon.definition,weapon.inventory)

# Same pure selection for the owning client's nominal artillery preview.
static func ground_selection_values(definition: WeaponDefinition,inventory: Dictionary) -> Dictionary:
	var first: AmmoDefinition
	for ammo: AmmoDefinition in definition.ammo_definitions:
		if int(inventory.get(ammo.ammo_id,0)) < definition.consumption_per_projectile: continue
		if first == null: first = ammo
		if is_finite(ammo.explosion_radius_m) and ammo.explosion_radius_m > 0: return {"reason":"eligible","ammo":ammo}
	return {"reason":"ammunition_insufficient"} if first == null else {"reason":"eligible","ammo":first}

static func penetration(ammo: AmmoDefinition, distance: float) -> float:
	if not is_finite(distance) or distance < 0: return NAN
	if ammo.damage_type == "chemical": return ammo.anchor_penetration
	if ammo.damage_type != "kinetic": return NAN
	if is_finite(ammo.confirmed_decay_coefficient):
		return maxf(5.0,ammo.penetration_upper-ammo.confirmed_decay_coefficient*log(1.0+distance/100.0))
	if ammo.test_curve == "baseline_cannon_log":
		return maxf(ammo.minimum_penetration,ammo.anchor_penetration*log(2.0)/log(1.0+maxf(1.0,distance)/ammo.anchor_distance_m))
	if ammo.anchor_distance_m <= 0 or ammo.penetration_upper < 0: return NAN
	if distance >= ammo.anchor_distance_m: return ammo.anchor_penetration
	if distance == 0: return ammo.penetration_upper
	if ammo.test_curve != "normalized_gun_log" or ammo.test_log_shape <= 0: return NAN
	return ammo.penetration_upper-(ammo.penetration_upper-ammo.anchor_penetration)*log(1.0+ammo.test_log_shape*distance/ammo.anchor_distance_m)/log(1.0+ammo.test_log_shape)

static func expected_damage(ammo: AmmoDefinition, p: float, armor: float, reduction: float, ignore: float) -> float:
	if not is_finite(p) or p < 5 or armor < 5 or not is_finite(armor) or ammo.nominal_damage < 0 or not is_finite(ammo.nominal_damage) or reduction < 0 or reduction > 1 or ignore < 0 or ignore > 1: return NAN
	var value := ammo.nominal_damage
	if ammo.damage_type == "kinetic":
		value *= minf(p/armor,1.0)
	elif ammo.damage_type == "chemical":
		if p <= 0.1*armor: value = 0
		elif p < 10*armor: value *= p*p/(p*p+armor*armor)
	else: return NAN
	return value*(1.0-reduction*(1.0-ignore))

static func select(weapon: RuntimeWeaponInstance, inputs: Dictionary,sample: Dictionary = {}) -> Dictionary:
	var target := weapon.target
	if target == null: return {"reason":"no_target"}
	# Ground fire has no target armor; explicit user selection rule applies.
	if target.kind != AttackTarget.Kind.UNIT: return ground_selection(weapon)
	var state := target.state()
	if state == null: return {"reason":"target_invalid"}
	var origin: Vector3 = sample.get("position",weapon.world_position())
	var target_position: Vector3 = sample.get("target",target.position())
	var face := state.armor_direction(origin,target_position,float(sample.get("target_yaw",state.yaw)))
	var definition := state.definition
	var reductions: Array = inputs.get("cover_reductions",[])
	var reduction := 0.0 # Formal default: no applicable proportional reduction.
	for entry: Variant in reductions:
		if not entry is float and not entry is int: return {"reason":"selection_configuration_missing"}
		if not is_finite(entry) or entry < 0 or entry > 1: return {"reason":"selection_configuration_missing"}
		reduction = maxf(reduction,entry)
	var distance := origin.distance_to(target_position)
	var best: AmmoDefinition
	var best_damage := -1.0
	for ammo: AmmoDefinition in weapon.definition.ammo_definitions:
		if int(weapon.inventory.get(ammo.ammo_id,0)) < weapon.definition.consumption_per_projectile: continue
		var armor: float = definition.protection_kinetic if ammo.damage_type == "kinetic" else definition.protection_chemical
		if state.unit_type() == UnitDefinition.UnitType.ARMORED_VEHICLE:
			armor = definition.kinetic_armor_by_face.get(face,-1) if ammo.damage_type == "kinetic" else definition.chemical_armor_by_face.get(face,-1)
		var score := expected_damage(ammo,penetration(ammo,distance),armor,reduction,weapon.definition.reduction_ignore)
		# A missing contender cannot silently lose the ranking to a known one.
		if not is_finite(score): return {"reason":"selection_configuration_missing"}
		if score > best_damage or (score == best_damage and ammo.ammo_id == weapon.fire_state.last_ammo_id):
			best = ammo
			best_damage = score
	return {"reason":"ammunition_insufficient"} if best == null else {"reason":"eligible","ammo":best,"preview_damage":best_damage}
