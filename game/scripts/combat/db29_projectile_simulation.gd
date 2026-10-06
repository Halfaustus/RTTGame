class_name DB29ProjectileSimulation
extends RefCounted

# Server-only fixed-step consumer. No node per projectile, radius or lifetime.
# The caller supplies already-authorized emissions at their actual times.
# Moving collision geometry must not be passed as stationary snapshots.
var collision := ProjectileCollisionWorld.new()
var time_seconds := 0.0
var failure_reason := ""
var halted := false
var slots: Array[Dictionary] = []
var free_slots: Array[int] = []
var active_slots: Array[int] = []
var generations: Array[int] = []
var active_ids: Dictionary = {}
var last_order := 0
var battlefield := Rect2()
var bounded := false
var profile := {"spawned":0,"impacts":0,"exits":0,"updates":0,"reuses":0,"failures":0}

# Runtime map geometry, not a unit parameter or a projectile lifetime.
func configure_bounds(value: Rect2) -> bool:
	if not value.position.is_finite() or not value.size.is_finite() or value.size.x <= 0 or value.size.y <= 0 or not active_slots.is_empty(): return false
	battlefield = value
	bounded = true
	return true

func _exit_fraction(start: Vector3,end: Vector3) -> float:
	if not bounded: return INF
	var a := Vector2(start.x,start.z)
	var b := Vector2(end.x,end.z)
	var low := battlefield.position
	var high := battlefield.end
	if a.x < low.x or a.y < low.y or a.x > high.x or a.y > high.y: return 0.0
	var fraction := INF
	for axis in range(2):
		if b[axis] < low[axis]: fraction = minf(fraction,(low[axis]-a[axis])/(b[axis]-a[axis]))
		elif b[axis] > high[axis]: fraction = minf(fraction,(high[axis]-a[axis])/(b[axis]-a[axis]))
	return fraction

# Exactly one physical step. No accumulated-time/drop/backlog policy implied.
# Invalid batches are rejected before any mutation and can be corrected/retried.
func step(events: Array[Dictionary] = [],units: ProjectileUnitMotion = null) -> Array[Dictionary]:
	if halted: return []
	failure_reason = ""
	var step_end := time_seconds + GravityBallistics.STEP_SECONDS
	if units != null and (not units.ready or absf(units.time_seconds-time_seconds) > ProjectileUnitMotion.TIME_TOLERANCE):
		failure_reason = "unit_motion_frame_invalid"
		return []
	var ordered := events.duplicate()
	for event: Dictionary in ordered:
		if not _valid(event,step_end):
			failure_reason = "invalid_emission_batch"
			return []
	ordered.sort_custom(func(a: Dictionary,b: Dictionary):
		var ta := float(a.get("time_seconds",NAN))
		var tb := float(b.get("time_seconds",NAN))
		return str(a.get("event_id","")) < str(b.get("event_id","")) if ta == tb else ta < tb)
	var seen := {}
	var next_order := last_order
	for event: Dictionary in ordered:
		if not _valid(event,step_end) or seen.has(event.event_id) or active_ids.has(event.event_id) or int(event.emission_order) <= next_order:
			failure_reason = "invalid_emission_batch"
			return []
		seen[event.event_id] = true
		next_order = int(event.emission_order)
	var output: Array[Dictionary] = []
	for event: Dictionary in ordered:
		var index: int
		if free_slots.is_empty():
			index = slots.size()
			slots.append({})
			generations.append(0)
		else:
			index = free_slots.pop_back()
			profile.reuses += 1
		generations[index] += 1
		# Only value source metadata and cached ammo reference survive firing.
		var source := {"event_id":event.event_id,"emission_order":event.emission_order,"unit_id":event.unit_id,"owner_player_id":event.owner_player_id,"weapon_instance_id":event.weapon_instance_id}
		var state := {"id":"projectile:"+str(event.event_id),"source":source,"ammo":event.ammo,"position":event.position,"velocity":event.velocity,"time_seconds":float(event.time_seconds),"distance_m":0.0,"ignore_house_id":int(event.get("ignore_house_id",0)),"ignore_target_house_id":int(event.get("ignore_target_house_id",0)),"generation":generations[index]}
		slots[index] = state
		active_slots.append(index)
		active_ids[event.event_id] = index
		output.append(_event(state,"spawn"))
		profile.spawned += 1
	last_order = next_order
	# Swap-remove active storage; chronological results do not depend on it.
	var cursor := 0
	while cursor < active_slots.size():
		var index := active_slots[cursor]
		var state := slots[index]
		var duration := clampf(step_end-float(state.time_seconds),0.0,GravityBallistics.STEP_SECONDS)
		var motion := GravityBallistics.segment(state.position,state.velocity,duration)
		profile.updates += 1
		var hit := {} if duration == 0.0 else collision.static_point_sweep(state.position,motion.position,collision.exclusions(int(state.source.unit_id),[state.ignore_house_id,state.ignore_target_house_id]),duration)
		if not hit.has("failure") and units != null and duration > 0.0:
			var unit_hit := units.sweep(state.position,motion.position,float(state.time_seconds),duration,int(state.source.unit_id),float(hit.get("fraction",1.0)))
			if unit_hit.has("failure"):
				hit = unit_hit
			elif not unit_hit.is_empty() and (hit.is_empty() or float(unit_hit.fraction)*duration < float(hit.fraction)*duration-ProjectileUnitMotion.TIME_TOLERANCE):
				hit = unit_hit # Indistinguishable times retain static priority.
		if hit.has("failure"):
			# Never erase the projectile on a failed query. Explicitly halt progress
			# for the whole timeline; later bodies must not advance after failure.
			failure_reason = str(hit.failure)
			halted = true
			profile.failures += 1
			break
		var impact := not hit.is_empty()
		var exit_at := _exit_fraction(state.position,motion.position)
		# Actual collision wins an indistinguishable boundary time.
		var exited := is_finite(exit_at) and (not impact or exit_at*duration < float(hit.fraction)*duration-ProjectileUnitMotion.TIME_TOLERANCE)
		var elapsed := duration * clampf(float(hit.get("fraction",1.0)),0.0,1.0)
		if exited: elapsed = duration*exit_at
		if impact or exited:
			motion = GravityBallistics.segment(state.position,state.velocity,elapsed)
		state.position = motion.position
		state.velocity = motion.velocity
		state.distance_m += motion.distance
		state.time_seconds += elapsed
		if not impact and not exited:
			cursor += 1
			continue
		var terminal := _event(state,"battlefield_exit" if exited else "impact")
		if not exited: terminal.merge({"point":hit.point,"normal":hit.normal,"object_id":hit.object_id,"object_category":hit.get("object_category",""),"hit_unit_id":hit.get("unit_id",0),"hit_unit_type":hit.get("unit_type",-1)},true)
		output.append(terminal)
		active_ids.erase(state.source.event_id)
		slots[index] = {} # Clear cached ammo, source and ignore state on reuse.
		free_slots.append(index)
		active_slots[cursor] = active_slots.back()
		active_slots.pop_back()
		if exited: profile.exits += 1
		else: profile.impacts += 1
	if failure_reason.is_empty(): time_seconds = step_end
	# Only actual events are sorted, never all surviving projectiles. There is
	# no destructive settlement here; future settlement must revalidate queries.
	output.sort_custom(func(a: Dictionary,b: Dictionary):
		if a.time_seconds != b.time_seconds: return a.time_seconds < b.time_seconds
		if a.projectile_id != b.projectile_id: return a.projectile_id < b.projectile_id
		return a.reason == "spawn" and b.reason != "spawn")
	return output

func _valid(event: Dictionary,step_end: float) -> bool:
	for key: String in ["event_id","emission_order","unit_id","owner_player_id","weapon_instance_id","position","velocity","time_seconds","ammo"]:
		if not event.has(key): return false
	if not event.position is Vector3 or not event.velocity is Vector3 or not event.ammo is AmmoDefinition: return false
	var ammo: AmmoDefinition = event.ammo
	var timestamp := float(event.time_seconds)
	var speed: float = event.velocity.length()
	var launch_valid := is_finite(speed) and speed > 0.0
	if not ammo.distance_selected_launch:
		launch_valid = launch_valid and is_finite(ammo.initial_speed_mps) and ammo.initial_speed_mps > 0.0 and absf(speed-ammo.initial_speed_mps) <= maxf(0.001,ammo.initial_speed_mps*0.000001)
	return not str(event.event_id).is_empty() and event.position.is_finite() and event.velocity.is_finite() and is_finite(timestamp) and timestamp >= time_seconds and timestamp <= step_end and launch_valid

func _event(state: Dictionary,reason: String) -> Dictionary:
	return {"reason":reason,"projectile_id":state.id,"source_event_id":state.source.event_id,"emission_order":state.source.emission_order,"unit_id":state.source.unit_id,"owner_player_id":state.source.owner_player_id,"weapon_instance_id":state.source.weapon_instance_id,"ammo_definition_id":state.ammo.ammo_id,"time_seconds":state.time_seconds,"position":state.position,"velocity":state.velocity,"distance_m":state.distance_m,"slot_generation":state.generation,"acceleration":GravityBallistics.GRAVITY}

func active_spawns(ordered: bool = true) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in active_slots: result.append(_event(slots[index],"spawn"))
	if ordered: result.sort_custom(func(a: Dictionary,b: Dictionary): return a.emission_order < b.emission_order)
	return result
