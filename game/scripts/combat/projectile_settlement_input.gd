class_name ProjectileSettlementInput
extends RefCounted

static func key(input: Dictionary) -> Variant:
	var sequence: int = input.get("impact_sequence",0)
	return input.emission_order if sequence == 0 else str(input.emission_order)+":"+str(sequence)

static func effect_id(input: Dictionary) -> String:
	return input.source_event_id if not input.has("impact_sequence") else input.source_event_id+":hit:"+str(input.impact_sequence)

# Server-only values captured before a pooled slot is cleared. This is not a
# replay format or a public projectile payload. Missing configuration is null,
# never zero; consumers must validate the fields needed by their own domain.
static func ammunition(ammo: AmmoDefinition) -> Dictionary:
	var result := {"ammo_id":ammo.ammo_id,"damage_type":ammo.damage_type,
		"distance_selected_launch":ammo.distance_selected_launch}
	for field: String in ["initial_speed_mps","nominal_damage","penetration_upper",
		"anchor_distance_m","anchor_penetration","minimum_penetration",
		"explosion_radius_m","explosion_radius_squared","inverse_explosion_radius_squared",
		"suppression","module_damage","confirmed_decay_coefficient"]:
		var value: float = ammo.get(field)
		result[field] = value if is_finite(value) and value >= 0.0 else null
	result.curve_description = ammo.curve_description
	result.test_curve = ammo.test_curve
	result.test_log_shape = ammo.test_log_shape if is_finite(ammo.test_log_shape) and ammo.test_log_shape >= 0.0 else null
	return result

static func terminal(event: Dictionary, ammo_values: Dictionary,weapon_values: Dictionary = {}) -> Dictionary:
	var reason: String = event.reason
	var kind := "battlefield_exit" if reason == "battlefield_exit" else "unit_impact" if event.get("hit_unit_id",0) > 0 else "static_impact"
	var result := {"kind":kind,"reason":reason,"projectile_id":event.projectile_id,
		"source_event_id":event.source_event_id,"emission_order":event.emission_order,
		"slot_generation":event.slot_generation,"source_unit_id":event.unit_id,
		"source_player_id":event.owner_player_id,"weapon_instance_id":event.weapon_instance_id,
		"ammo_definition_id":ammo_values.ammo_id,"ammo_values":ammo_values.duplicate(true),
		"weapon_values":weapon_values.duplicate(true),
		"time_seconds":event.time_seconds,"position":_vector(event.position),
		"velocity":_vector(event.velocity),"distance_m":event.distance_m}
	if reason == "impact":
		result.merge({"point":_vector(event.point),"normal":_vector(event.normal),
			"object_id":event.object_id,"object_category":event.object_category,
			"hit_unit_id":event.hit_unit_id,"hit_unit_type":event.hit_unit_type})
	return result

static func _vector(value: Vector3) -> Array:
	return [value.x,value.y,value.z]
