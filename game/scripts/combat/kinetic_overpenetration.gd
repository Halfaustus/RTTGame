class_name KineticOverpenetration
extends RefCounted

const ENTRY_RATIO := 2.0
const HEALTH_FRACTION := 0.1

# Server-only entry-time tangent approximation explicitly confirmed by owner.
static func decide(input: Dictionary,unit: UnitState,frame: FiringFrame,penetration: float,armor: float) -> Dictionary:
	var result := {"ok":true,"continues":false}
	if input.ammo_values.damage_type != "kinetic" or float(input.ammo_values.explosion_radius_m) > 0: return result
	if penetration < ENTRY_RATIO*armor: return result
	var loss: float = input.get("penetration_loss",0.0)
	if unit.unit_type() == UnitDefinition.UnitType.INFANTRY:
		return {"ok":true,"continues":true,"penetration_loss_next":loss+armor,"exit_face":"uniform"}
	if frame.motion == null or not frame.motion.records.has(unit.unit_id): return {"ok":false,"reason":"overpenetration_geometry_missing"}
	var record: Dictionary = frame.motion.records[unit.unit_id]
	var fraction := frame.motion.record_fraction(record,float(input.time_seconds))
	var basis: Basis = record.basis.slerp(record.end_basis,fraction)
	var center: Vector3 = record.start.lerp(record.end,fraction)
	var extents: Vector3 = record.extents.lerp(record.end_extents,fraction)
	var point := DirectHitSettlement.vector(input.point)
	var direction := DirectHitSettlement.vector(input.velocity).normalized()
	var entry_normal := DirectHitSettlement.vector(input.normal)
	# Inside-origin queries have zero entry normal. Tangency cannot traverse a hull.
	if entry_normal.length_squared() == 0 or direction.dot(entry_normal) >= 0: return result
	var exit := exit_surface(basis.inverse()*(point-center),basis.inverse()*direction,extents)
	if exit.is_empty() or exit.face == "bottom": return result
	var outgoing: Variant = unit.definition.kinetic_armor_by_face.get(exit.face)
	if not ImpactDamageRules.number(outgoing,5.0): return {"ok":false,"reason":"overpenetration_exit_armor_missing"}
	result.exit_face = exit.face
	result.exit_armor = float(outgoing)
	if penetration-armor < float(outgoing): return result
	result.continues = true
	result.penetration_loss_next = loss+armor+float(outgoing)
	return result

static func exit_surface(point: Vector3,direction: Vector3,extents: Vector3) -> Dictionary:
	if not point.is_finite() or not direction.is_finite() or not extents.is_finite(): return {}
	var tolerance := ProjectileUnitMotion.SHAPE_ERROR_METERS
	if absf(point.x) > extents.x+tolerance or absf(point.y) > extents.y+tolerance or absf(point.z) > extents.z+tolerance: return {}
	var distance := INF
	var face := ""
	for axis: int in 3:
		if direction[axis] == 0: continue
		var sign_value := 1.0 if direction[axis] > 0 else -1.0
		var at := (sign_value*extents[axis]-point[axis])/direction[axis]
		if at < distance:
			distance = at
			face = "side" if axis == 0 else ("top" if sign_value > 0 else "bottom") if axis == 1 else ("rear" if sign_value > 0 else "front")
	return {} if distance <= tolerance or not is_finite(distance) else {"face":face,"distance":distance}

# Nominal first-target preview only; not collision authority or flight simulation.
static func preview(unit: UnitState,origin: Vector3,target: Vector3,yaw: float,p: float,armor: float) -> Dictionary:
	if p < ENTRY_RATIO*armor: return {"ok":true,"continues":false}
	if unit.unit_type() == UnitDefinition.UnitType.INFANTRY: return {"ok":true,"continues":true}
	var inverse := Basis(Vector3.UP,yaw).inverse()
	var extents := unit.hitbox_extents()
	var start := inverse*(origin-target)
	var hit := ProjectileUnitMotion._box(start,Vector3.ZERO,extents)
	if hit.is_empty() or hit.normal == Vector3.ZERO: return {"ok":true,"continues":false}
	var direction := (-start).normalized()
	var outgoing := exit_surface(start.lerp(Vector3.ZERO,hit.fraction),direction,extents)
	if outgoing.is_empty() or outgoing.face == "bottom": return {"ok":true,"continues":false}
	var value: Variant = unit.definition.kinetic_armor_by_face.get(outgoing.face)
	if not ImpactDamageRules.number(value,5.0): return {"ok":false}
	return {"ok":true,"continues":p-armor >= float(value)}
