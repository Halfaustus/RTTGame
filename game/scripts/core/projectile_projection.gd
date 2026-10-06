class_name ProjectileProjection
extends RefCounted

# Only the global emission order is public; never derive identity from a source.
static func spawn(event: Dictionary) -> Dictionary:
	if not _motion_valid(event) or not event.get("emission_order") is int or event.emission_order <= 0:
		return {}
	return {"projectile_id": "flight:%d" % event.emission_order,
		"emission_order": event.emission_order, "time_seconds": event.time_seconds,
		"position": event.position, "velocity": event.velocity, "acceleration": event.acceleration}

static func terminal(event: Dictionary) -> Dictionary:
	if not event.get("emission_order") is int or event.emission_order <= 0:
		return {}
	if event.get("reason") not in ["impact", "battlefield_exit"] or not _position_valid(event):
		return {}
	return {"projectile_id": "flight:%d" % event.emission_order,
		"time_seconds": event.time_seconds, "position": event.position, "reason": event.reason}

static func batch(arguments: Array) -> Array:
	if arguments.size() != 3 or not arguments[0] is Array or not arguments[1] is Array:
		return []
	if not arguments[2] is float or not is_finite(arguments[2]) or arguments[2] < 0:
		return []
	var spawns: Array[Dictionary] = []
	var terminals: Array[Dictionary] = []
	for event: Variant in arguments[0]:
		if not event is Dictionary: return []
		var row := spawn(event)
		if row.is_empty() or row.time_seconds > arguments[2]: return []
		spawns.append(row)
	for event: Variant in arguments[1]:
		if not event is Dictionary: return []
		var row := terminal(event)
		if row.is_empty() or row.time_seconds > arguments[2]: return []
		terminals.append(row)
	return [spawns, terminals, arguments[2]]

static func _position_valid(event: Dictionary) -> bool:
	return event.get("position") is Vector3 and event.position.is_finite() and (event.get("time_seconds") is float or event.get("time_seconds") is int) and is_finite(float(event.time_seconds)) and event.time_seconds >= 0

static func _motion_valid(event: Dictionary) -> bool:
	return _position_valid(event) and event.get("velocity") is Vector3 and event.velocity.is_finite() and event.get("acceleration") is Vector3 and event.acceleration.is_finite()
