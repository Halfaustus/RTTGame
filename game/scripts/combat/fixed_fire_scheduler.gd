class_name FixedFireScheduler
extends RefCounted

# Uses the existing FireSimulation and RuntimeWeaponInstance as the ONLY
# timer/inventory authority. Heap entries are transient due-event indices,
# not additional per-physical-weapon firing states.
static func step(fire: FireSimulation,aiming: AimingSimulation,frame: FiringFrame = null) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var start := fire.time_seconds
	var end := start + GravityBallistics.STEP_SECONDS
	fire.last_tick += 1
	var heap: Array[Dictionary] = []
	var channels: Array[Dictionary] = []
	for unit: UnitState in aiming.units.values():
		for weapon: RuntimeWeaponInstance in unit.runtime_weapons:
			var entry := {"weapon":weapon,"cursor":start,"time":start}
			channels.append(entry)
			var state := weapon.fire_state
			state.can_fire = false
			state.reason = _eligibility(weapon,aiming,frame,start,true)
			if state.reason != "eligible": continue
			var wait := _wait(weapon,aiming.inputs.get(unit.unit_id,{}))
			if frame != null: wait = maxf(wait,float(frame.weapons[weapon.instance_id].ready)-start)
			if not is_finite(wait):
				state.reason = "fire_configuration_missing"
				continue
			entry.time = start + wait
			if entry.time <= end + FireSimulation.TIME_EPSILON: _push(heap,entry)
	while not heap.is_empty():
		var entry := _pop(heap)
		var weapon: RuntimeWeaponInstance = entry.weapon
		var at := minf(float(entry.time),end)
		_advance(fire,entry,at,aiming)
		var event := _emit(fire,weapon,at,aiming,frame)
		if event.is_empty(): continue
		events.append(event)
		var wait := _wait(weapon,aiming.inputs.get(weapon.owner_state().unit_id,{}))
		# Positive progress follows either the interval or per-shot preparation.
		if not is_finite(wait) or wait <= FireSimulation.TIME_EPSILON:
			weapon.fire_state.reason = "fire_configuration_missing"
			continue
		entry.time = at + wait
		if entry.time <= end + FireSimulation.TIME_EPSILON: _push(heap,entry)
	for entry: Dictionary in channels:
		_advance(fire,entry,end,aiming)
		var state: WeaponFireState = entry.weapon.fire_state
		if state.reason == "eligible":
			state.reason = "loading" if state.loading else "interval"
			state.phase = WeaponFireState.Phase.LOADING if state.loading else WeaponFireState.Phase.INTERVAL
	fire.time_seconds = end
	return events

static func _eligibility(weapon: RuntimeWeaponInstance,aiming: AimingSimulation,frame: FiringFrame = null,at: float = 0.0,scheduling: bool = false) -> String:
	if not weapon.owning_node_valid(): return "owner_invalid"
	var sample := frame.pose(weapon,at) if frame != null and weapon.target != null else {}
	var reason := aiming.eligibility(weapon,sample)
	if reason != "eligible": return reason
	if weapon.definition.definition_id == "W_M252" and not aiming.artillery_tasks.has(weapon.instance_id): return "artillery_requires_t"
	if aiming.artillery_tasks.has(weapon.instance_id):
		var task: Dictionary = aiming.artillery_tasks[weapon.instance_id]
		if task.get("finished",false): return "artillery_task_complete"
		var distance: float = sample.get("position",weapon.world_position()).distance_to(sample.get("target",weapon.target.position()))
		if distance < float(task.minimum): return "below_minimum_range"
	if frame == null:
		if not weapon.is_aimed or not weapon.aim_timer_complete: return "not_aimed"
	elif not is_finite(float(sample.ready)) or (not scheduling and at+FireSimulation.TIME_EPSILON < float(sample.ready)): return "not_aimed"
	# No start/end motion sampling contract exists in the coordinator yet.
	if frame == null and (aiming.moving.call(weapon.owner_state().unit_id) or aiming.target_velocities.get(weapon.owner_state().unit_id,Vector3.ZERO) != Vector3.ZERO or aiming.target_velocities.get(weapon.target.unit_id,Vector3.ZERO) != Vector3.ZERO): return "motion_timeline_not_integrated"
	var definition := weapon.definition
	if definition.capacity <= 0 or not is_finite(definition.preparation_seconds) or definition.preparation_seconds <= 0.0 or not is_finite(weapon.shot_interval()) or weapon.shot_interval() < 0.0 or (weapon.shot_interval() == 0.0 and not definition.preparation_cadence): return "fire_configuration_missing"
	if definition.projectile != null: return "legacy_projectile_configuration"
	if definition.spread_policy != "fixed_world_radius" or not is_finite(definition.spread_radius_m) or definition.spread_radius_m < 0.0: return "spread_configuration_missing"
	return "eligible"

static func _wait(weapon: RuntimeWeaponInstance,inputs: Dictionary) -> float:
	var wait := weapon.fire_state.interval_remaining
	if weapon.fire_state.loading:
		var multiplier: float = inputs.get("loading_module_multiplier",1.0)
		if not weapon.definition.mechanical_loading: multiplier *= float(inputs.get("personnel_load_multiplier",1.0))
		var duration := weapon.loading_seconds()*multiplier
		if not is_finite(duration) or duration <= 0.0: return NAN
		wait = maxf(wait,(1.0-weapon.fire_state.loading_progress)*duration)
	return wait

static func _advance(fire: FireSimulation,entry: Dictionary,at: float,aiming: AimingSimulation) -> void:
	var weapon: RuntimeWeaponInstance = entry.weapon
	var delta := maxf(0.0,at-float(entry.cursor))
	if not weapon.owning_node_valid():
		entry.cursor = at
		return
	weapon.fire_state.interval_remaining = maxf(0.0,weapon.fire_state.interval_remaining-delta)
	if weapon.fire_state.interval_remaining <= FireSimulation.TIME_EPSILON: weapon.fire_state.interval_remaining = 0.0
	fire._advance_loading(weapon,delta,aiming.inputs.get(weapon.owner_state().unit_id,{}))
	entry.cursor = at

static func _emit(fire: FireSimulation,weapon: RuntimeWeaponInstance,at: float,aiming: AimingSimulation,frame: FiringFrame = null) -> Dictionary:
	var state := weapon.fire_state
	state.reason = _eligibility(weapon,aiming,frame,at)
	if state.reason != "eligible": return {}
	if state.loading or state.interval_remaining > FireSimulation.TIME_EPSILON:
		state.reason = "loading" if state.loading else "interval"
		return {}
	var definition := weapon.definition
	var count := definition.consumption_per_projectile
	if weapon.pending_rounds < count:
		state.reason = "pending_recovery_undefined"
		return {}
	var sample := frame.pose(weapon,at) if frame != null else {}
	var selection := AmmoSelection.select(weapon,aiming.inputs.get(weapon.target.unit_id,{}),sample)
	if aiming.artillery_tasks.has(weapon.instance_id):
		var task: Dictionary = aiming.artillery_tasks[weapon.instance_id]
		selection = {"reason":"eligible","ammo":task.ammo} if int(weapon.inventory.get(task.ammo.ammo_id,0)) >= definition.consumption_per_projectile else {"reason":"ammunition_insufficient"}
		if selection.reason != "eligible": task.finished = true
	fire.profile["selection_queries"] = fire.profile.get("selection_queries",0)+1
	state.reason = selection.reason
	if state.reason != "eligible": return {}
	var ammo: AmmoDefinition = selection.ammo
	if not is_finite(ammo.initial_speed_mps) or ammo.initial_speed_mps <= 0.0:
		state.reason = "projectile_configuration_missing"
		return {}
	var inputs: Dictionary = aiming.inputs.get(weapon.owner_state().unit_id,{})
	var position: Vector3 = sample.get("position",weapon.world_position())
	var yaw: float = sample.get("yaw",weapon.world_yaw())
	var origin := DirectBallistics.sampled_muzzle(weapon,position,yaw,inputs)
	var target: Vector3 = sample.get("target",weapon.target.position())
	if not origin.is_finite() or not target.is_finite():
		state.reason = "spatial_configuration_invalid"
		return {}
	var offset := target-origin
	var required_yaw := atan2(-(target-position).x,-(target-position).z)
	if absf(wrapf(required_yaw-yaw,-PI,PI)) > deg_to_rad(Prototype05DCatalog.AIM_TOLERANCE_DEGREES):
		state.reason = "not_aimed"
		return {}
	var radius := definition.spread_radius_m*float(inputs.get("spread_multiplier",1.0))
	if sample.get("moving",false):
		# Existing state-input multiplier; missing moving spread stays explicit.
		if not inputs.has("moving_spread_multiplier"):
			state.reason = "moving_spread_configuration_missing"
			return {}
		radius *= float(inputs.moving_spread_multiplier)
	if not is_finite(radius) or radius < 0.0:
		state.reason = "spread_configuration_missing"
		return {}
	var spread := DirectBallistics.spread_offset(fire.random,radius,offset.normalized())
	fire.profile["spread_samples"] = fire.profile.get("spread_samples",0)+1
	var solution := GravityBallistics.high(origin,target,ammo.initial_speed_mps,spread) if aiming.artillery_tasks.has(weapon.instance_id) else GravityBallistics.direct(origin,target,sample.get("target_velocity",Vector3.ZERO),ammo.initial_speed_mps,spread)
	if not solution.has("solves"): solution.solves = 1
	fire.profile["ballistic_solves"] = fire.profile.get("ballistic_solves",0)+int(solution.solves)
	if not solution.valid:
		state.reason = "intercept_unreachable"
		if aiming.artillery_tasks.has(weapon.instance_id): aiming.artillery_tasks[weapon.instance_id].finished = true
		return {}
	# Automatic gravity/lead/spread compensation is separate from node turning.
	if not fire.fire_path_permission.is_valid():
		state.reason = "fire_path_configuration_missing"
		return {}
	if not fire.fire_path_permission.call(weapon,origin,solution.point,inputs):
		state.reason = "friendly_blocked"
		return {}
	if frame != null and not frame.friendly_clear(weapon,origin,solution.point,at):
		state.reason = "friendly_blocked"
		return {}
	var event := {"event_id":"%s:%s" % [weapon.instance_id,state.emission_count+1],"emission_order":fire.emission_order+1,"time_seconds":at,"unit_id":weapon.owner_state().unit_id,"owner_player_id":weapon.owner_state().owner_player_id,"weapon_instance_id":weapon.instance_id,"position":origin,"velocity":solution.velocity,"ammo":ammo,"consumed":count,"ignore_house_id":int(inputs.get("house_id",0)),"ignore_target_house_id":int(aiming.inputs.get(weapon.target.unit_id,{}).get("house_id",0))}
	# All configuration, geometry and permissions checked before atomic debit.
	weapon.consume(ammo.ammo_id,count)
	weapon.pending_rounds -= count
	fire.emission_order += 1
	state.emission_count += 1
	state.last_emission_tick = fire.last_tick
	state.last_ammo_id = ammo.ammo_id
	state.interval_remaining = weapon.shot_interval()
	if aiming.artillery_tasks.has(weapon.instance_id):
		var task: Dictionary = aiming.artillery_tasks[weapon.instance_id]
		# Enforce count at the emission instant, including multiple shots in a step.
		if task.remaining > 0: task.remaining -= 1
		if task.remaining == 0: task.finished = true
		if task.remaining < 0 and not weapon.has_ammunition(): task.finished = true
	if definition.preparation_cadence or weapon.pending_rounds < count:
		state.loading = true
		state.loading_progress = 0.0
	state.reason = "loading" if state.loading else "interval"
	state.phase = WeaponFireState.Phase.LOADING if state.loading else WeaponFireState.Phase.INTERVAL
	if weapon.forced_emissions_remaining > 0:
		weapon.forced_emissions_remaining -= 1
		if weapon.forced_emissions_remaining == 0: weapon.clear_target()
	return event

static func _before(a: Dictionary,b: Dictionary) -> bool:
	return a.weapon.instance_id < b.weapon.instance_id if a.time == b.time else a.time < b.time

static func _push(heap: Array[Dictionary],entry: Dictionary) -> void:
	heap.append(entry)
	var index := heap.size()-1
	while index > 0:
		var parent := (index-1)/2
		if not _before(heap[index],heap[parent]): break
		var previous := heap[parent]
		heap[parent] = heap[index]
		heap[index] = previous
		index = parent

static func _pop(heap: Array[Dictionary]) -> Dictionary:
	var result := heap[0]
	var tail: Dictionary = heap.pop_back()
	if heap.is_empty(): return result
	heap[0] = tail
	var index := 0
	while index*2+1 < heap.size():
		var child := index*2+1
		if child+1 < heap.size() and _before(heap[child+1],heap[child]): child += 1
		if not _before(heap[child],heap[index]): break
		var previous := heap[index]
		heap[index] = heap[child]
		heap[child] = previous
		index = child
	return result
