class_name ExplosionSettlement
extends RefCounted

# Pure plan preparation. Commit uses the existing explicit member/hull entrypoints.
static func prepare(input: Dictionary,aiming: AimingSimulation,sample: FiringFrame) -> Dictionary:
	var ammo: Dictionary = input.ammo_values
	var weapon: Dictionary = input.get("weapon_values",{})
	for field: String in ["explosion_radius_m","explosion_radius_squared","inverse_explosion_radius_squared"]:
		if not ImpactDamageRules.number(ammo.get(field),0.0) or float(ammo[field]) <= 0: return {"ok":false,"reason":"explosion_cache_missing"}
	if not ImpactDamageRules.number(ammo.get("suppression"),0.0) or not weapon.get("attack_top") is bool or not ImpactDamageRules.number(weapon.get("reduction_ignore"),0.0): return {"ok":false,"reason":"explosion_configuration_missing"}
	if sample.motion == null or not sample.motion.ready: return {"ok":false,"reason":"explosion_geometry_missing"}
	var point := DirectHitSettlement.vector(input.point)
	var at: float = input.time_seconds
	var ids := ExplosionGeometry.nearby(sample.motion,point,float(ammo.explosion_radius_m))
	if input.kind == "unit_impact" and not ids.has(input.hit_unit_id): ids.append(input.hit_unit_id); ids.sort()
	var effects: Array[Dictionary] = []
	var suppression: Array[Dictionary] = []
	var affected: Array = []
	for id: int in ids:
		var unit: UnitState = aiming.units.get(id)
		if unit == null or unit.health <= 0: continue
		var cover: Variant = aiming.inputs.get(id,{}).get("cover_reductions",[])
		if not cover is Array: return {"ok":false,"reason":"cover_configuration_invalid"}
		if unit.unit_type() == UnitDefinition.UnitType.INFANTRY:
			var positions := sample.member_positions(id,at)
			var members := {}
			var seen := {}
			for member: SoldierState in unit.members:
				if member.member_id <= 0 or seen.has(member.member_id): return {"ok":false,"reason":"explosion_member_identity_invalid"}
				seen[member.member_id] = true
				if not is_finite(member.health) or member.health < 0 or member.health > 5: return {"ok":false,"reason":"explosion_member_health_invalid"}
				if member.health <= 0: continue
				if members.has(member.member_id) or not positions.has(member.member_id): return {"ok":false,"reason":"explosion_member_geometry_invalid"}
				members[member.member_id] = member
			var member_ids := members.keys()
			member_ids.sort()
			var reached := false
			for member_id: int in member_ids:
				var position: Vector3 = positions[member_id]
				if not position.is_finite(): return {"ok":false,"reason":"explosion_member_geometry_invalid"}
				var distance_squared := point.distance_squared_to(position)
				if distance_squared >= float(ammo.explosion_radius_squared): continue
				reached = true
				var value := effect(input,unit,cover,distance_squared,"uniform",member_id)
				if not value.ok: return value
				effects.append(value)
			if reached:
				affected.append(id)
				suppression.append({"unit_id":id,"amount":ammo.suppression,"emission_order":input.emission_order,
					"source_event_id":input.source_event_id,"ammo_definition_id":ammo.ammo_id,
					"time_seconds":at,"source_unit_id":input.source_unit_id,"source_player_id":input.source_player_id})
		else:
			var geometry := ExplosionGeometry.closest(sample.motion,id,point,at)
			if not geometry.ok: return geometry
			var direct: bool = input.kind == "unit_impact" and id == int(input.hit_unit_id)
			var distance_squared: float = 0.0 if direct else geometry.distance_squared
			if distance_squared >= float(ammo.explosion_radius_squared): continue
			var zero_direction: bool = Vector2(geometry.velocity.x,geometry.velocity.z).length_squared() == 0.0
			var face := ImpactDamageRules.face(DirectHitSettlement.vector(input.velocity),DirectHitSettlement.vector(input.normal),geometry.yaw,weapon.attack_top) if direct else ImpactDamageRules.face(geometry.velocity,-geometry.velocity,geometry.yaw,weapon.attack_top or zero_direction)
			if face == "unknown": return {"ok":false,"reason":"explosion_face_undefined"}
			var value := effect(input,unit,cover,distance_squared,face,0)
			if not value.ok: return value
			effects.append(value)
			affected.append(id)
	return {"ok":true,"affected_unit_ids":affected,"effects":effects,"suppression_inputs":suppression}

static func effect(input: Dictionary,unit: UnitState,cover: Array,distance_squared: float,face: String,member_id: int) -> Dictionary:
	var ammo: Dictionary = input.ammo_values.duplicate(true)
	var factor := ExplosionGeometry.attenuation(distance_squared,float(ammo.explosion_radius_squared),float(ammo.inverse_explosion_radius_squared))
	if not ImpactDamageRules.number(ammo.get("nominal_damage"),0.0) or not is_finite(factor): return {"ok":false,"reason":"explosion_configuration_missing"}
	ammo.nominal_damage *= factor
	var kinetic: bool = ammo.damage_type == "kinetic"
	var armor: float = unit.definition.protection_kinetic if kinetic else unit.definition.protection_chemical
	if face != "uniform": armor = float((unit.definition.kinetic_armor_by_face if kinetic else unit.definition.chemical_armor_by_face).get(face,-1.0))
	var value := ImpactDamageRules.damage(ammo,float(input.distance_m),armor,cover,float(input.weapon_values.reduction_ignore))
	if not value.ok: return value
	value.merge({"unit_id":unit.unit_id,"member_id":member_id,"face":face,"distance_squared":distance_squared,"attenuation":factor})
	return value
