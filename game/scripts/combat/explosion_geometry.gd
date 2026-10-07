class_name ExplosionGeometry
extends RefCounted

# One shared spatial query per blast; source units are deliberately included.
static func nearby(motion: ProjectileUnitMotion,point: Vector3,radius: float) -> Array:
	var candidates := {}
	var bounds := AABB(point-Vector3.ONE*radius,Vector3.ONE*radius*2.0)
	for cell: Vector3i in ProjectileUnitMotion._covered(bounds):
		for id: Variant in motion.cells.get(cell,[]):
			if motion.records.has(id) and ProjectileUnitMotion._overlaps(bounds,motion.records[id].bounds): candidates[id] = true
	var ids := candidates.keys()
	ids.sort()
	return ids

static func closest(motion: ProjectileUnitMotion,id: int,point: Vector3,at: float) -> Dictionary:
	if not motion.records.has(id): return {"ok":false,"reason":"explosion_geometry_missing"}
	var row: Dictionary = motion.records[id]
	var fraction := motion.record_fraction(row,at)
	var center: Vector3 = row.start.lerp(row.end,fraction)
	var basis: Basis = row.basis.slerp(row.end_basis,fraction)
	var extents: Vector3 = row.extents.lerp(row.end_extents,fraction)
	var local: Vector3 = basis.inverse()*(point-center)
	var nearest := local.clamp(-extents,extents)
	var delta := local-nearest
	return {"ok":true,"distance_squared":delta.length_squared(),"velocity":center-point,
		"normal":basis*delta,"yaw":basis.get_euler().y}

static func attenuation(distance_squared: float,radius_squared: float,inverse_radius_squared: float) -> float:
	if not is_finite(distance_squared) or distance_squared < 0 or not is_finite(radius_squared) or radius_squared <= 0 or not is_finite(inverse_radius_squared) or inverse_radius_squared <= 0: return NAN
	if distance_squared >= radius_squared: return 0.0
	var remaining := 1.0-distance_squared*inverse_radius_squared
	return remaining*remaining
