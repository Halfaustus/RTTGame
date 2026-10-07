class_name ImpactDamageRules
extends RefCounted

# Values from the emission snapshot. No Resource reconstruction or curve setup
# on impact; unknown required fields fail rather than granting zero protection.
static func penetration(ammo: Dictionary,distance: float) -> float:
	if not is_finite(distance) or distance < 0: return NAN
	if ammo.get("damage_type") == "chemical":
		return float(ammo.anchor_penetration) if number(ammo.get("anchor_penetration"),5.0) else NAN
	if ammo.get("damage_type") != "kinetic" or not number(ammo.get("penetration_upper"),5.0) or not number(ammo.get("confirmed_decay_coefficient"),0.0): return NAN
	return maxf(5.0,float(ammo.penetration_upper)-float(ammo.confirmed_decay_coefficient)*log(1.0+distance/100.0))

static func damage(ammo: Dictionary,distance: float,armor: float,cover: Array,ignore: float,loss: float = 0.0) -> Dictionary:
	var p := penetration(ammo,distance)
	if not is_finite(p): return {"ok":false,"reason":"impact_configuration_missing"}
	if not number(loss,0.0): return {"ok":false,"reason":"penetration_loss_invalid"}
	if ammo.get("damage_type") == "kinetic": p = maxf(0.0,p-loss)
	if not is_finite(p) or not is_finite(armor) or armor < 5 or not number(ammo.get("nominal_damage"),0.0) or not is_finite(ignore) or ignore < 0 or ignore > 1:
		return {"ok":false,"reason":"impact_configuration_missing"}
	var reduction := 0.0 # Confirmed default: no applicable cover, not a missing field.
	for item: Variant in cover:
		if not number(item,0.0) or float(item) > 1: return {"ok":false,"reason":"cover_configuration_invalid"}
		reduction = maxf(reduction,float(item))
	var factor := minf(p/armor,1.0)
	if ammo.damage_type == "chemical":
		factor = 0.0 if p <= 0.1*armor else 1.0 if p >= 10.0*armor else 1.0/(1.0+(armor/p)*(armor/p))
	var result := float(ammo.nominal_damage)*factor*(1.0-reduction*(1.0-ignore))
	if not is_finite(result): return {"ok":false,"reason":"impact_damage_nonfinite"}
	return {"ok":true,"penetration":p,"armor":armor,"damage":result}

static func face(velocity: Vector3,normal: Vector3,yaw: float,attack_top: bool) -> String:
	if not velocity.is_finite() or not normal.is_finite() or not is_finite(yaw): return "unknown"
	if attack_top or (normal.y > 0 and absf(normal.y) >= maxf(absf(normal.x),absf(normal.z))): return "top"
	var incoming := Vector2(-velocity.x,-velocity.z)
	if incoming.length_squared() == 0: return "unknown"
	var cosine := incoming.normalized().dot(Vector2(-sin(yaw),-cos(yaw)))
	if cosine >= cos(deg_to_rad(60.0)): return "front"
	if cosine <= cos(deg_to_rad(135.0)): return "rear"
	return "side"

static func nearest(unit: UnitState,point: Vector3,positions: Dictionary) -> int:
	var chosen := 0
	var best := INF
	for member: SoldierState in unit.members:
		if member.health <= 0: continue
		if not positions.has(member.member_id) or not positions[member.member_id] is Vector3 or not positions[member.member_id].is_finite(): return 0
		var distance: float = positions[member.member_id].distance_squared_to(point)
		if distance < best or (distance == best and (chosen == 0 or member.member_id < chosen)):
			best = distance
			chosen = member.member_id
	return chosen

static func number(value: Variant,minimum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum
