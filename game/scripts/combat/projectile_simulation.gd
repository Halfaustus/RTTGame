class_name ProjectileSimulation
extends RefCounted

var collision := ProjectileCollisionWorld.new()
var active: Dictionary[String,ProjectileState] = {}
var last_emission_order := 0 # Reliable ordered authoritative stream, constant memory dedup.
var last_tick := -1
var bounds := Rect2() # Explicit map bounds, empty only in isolated flight fixture.
var profile := {"spawned":0,"impacts":0,"expired":0,"boundary":0,"query_failed":0,"peak_active":0,"updates":0,"failures":0}
var failure_reason := ""

func consume(events: Array[Dictionary]) -> Array[Dictionary]:
	var spawns: Array[Dictionary] = []
	for event: Dictionary in events:
		var order := int(event.get("emission_order",0))
		if order <= last_emission_order: continue
		last_emission_order = order
		if not event.has("projectile") or not event.has("direction"):
			failure_reason = "projectile_configuration_missing"
			profile.failures += 1
			continue
		var configuration: Dictionary = event.projectile
		if configuration.get("trajectory","") != "direct" or not event.position.is_finite() or not event.direction.is_finite() or absf(event.direction.length_squared()-1) > 0.00001 or not is_finite(configuration.speed_mps) or configuration.speed_mps <= 0 or not is_finite(configuration.radius_m) or configuration.radius_m < 0 or not is_finite(configuration.lifetime_seconds) or configuration.lifetime_seconds <= 0:
			failure_reason = "projectile_configuration_invalid"
			profile.failures += 1
			continue
		var projectile := ProjectileState.new(event)
		active[projectile.id] = projectile
		spawns.append(projectile.spawn_event())
		profile.spawned += 1
		profile.peak_active = maxi(profile.peak_active,active.size())
	return spawns

func advance(delta: float, tick: int) -> Array[Dictionary]:
	var terminals: Array[Dictionary] = []
	if delta <= 0 or not is_finite(delta) or tick <= last_tick: return terminals
	last_tick = tick
	for projectile: ProjectileState in active.values():
		profile.updates += 1
		projectile.previous_position = projectile.position
		var duration := minf(delta,projectile.remaining)
		var end := projectile.position+projectile.velocity*duration
		var limit := boundary_fraction(projectile.position,end)
		var hit := collision.sweep(projectile.position,projectile.position.lerp(end,limit),projectile.radius,collision.exclusions(int(projectile.source.unit_id),[int(projectile.source.get("ignore_house_id",0)),int(projectile.source.get("ignore_target_house_id",0))]))
		var fraction := limit
		var reason := ""
		if hit.has("failure"):
			failure_reason = hit.failure
			profile.failures += 1
			fraction = 0
			reason = "query_failed"
		elif not hit.is_empty():
			fraction *= hit.fraction
			reason = "impact"
		elif limit < 1: reason = "map_boundary"
		elif duration >= projectile.remaining: reason = "expired"
		projectile.position = projectile.position.lerp(end,fraction)
		projectile.distance += projectile.previous_position.distance_to(projectile.position)
		projectile.elapsed += duration*fraction
		projectile.remaining = maxf(0,projectile.remaining-duration*fraction)
		if reason.is_empty(): continue
		projectile.terminal = true
		var event := projectile.spawn_event()
		event.merge({"reason":reason,"tick":tick,"time_seconds":projectile.source.time_seconds+projectile.elapsed,"distance_m":projectile.distance,"position":projectile.position,"point":hit.get("point",projectile.position),"normal":hit.get("normal",Vector3.ZERO),"incoming_direction":projectile.velocity.normalized(),"object_id":hit.get("object_id",""),"object_category":hit.get("object_category",""),"hit_unit_id":hit.get("unit_id",0),"explosion_radius_m":projectile.source.get("explosion_radius_m",-1) },true)
		event["hit_unit_type"] = hit.get("unit_type",-1)
		terminals.append(event)
		active.erase(projectile.id)
		profile[{"impact":"impacts","expired":"expired","map_boundary":"boundary","query_failed":"query_failed"}[reason]] += 1
	return terminals

func boundary_fraction(start: Vector3, end: Vector3) -> float:
	if bounds.size == Vector2.ZERO: return 1
	if start.x < bounds.position.x or start.x > bounds.end.x or start.z < bounds.position.y or start.z > bounds.end.y: return 0
	var fraction := 1.0
	for axis: int in [0,2]:
		var component := 0 if axis == 0 else 1
		if end[axis] < bounds.position[component]: fraction = minf(fraction,(bounds.position[component]-start[axis])/(end[axis]-start[axis]))
		elif end[axis] > bounds.end[component]: fraction = minf(fraction,(bounds.end[component]-start[axis])/(end[axis]-start[axis]))
	return clampf(fraction,0,1)
