class_name OrderedProjectileStep
extends RefCounted

# Predictions are private, non-destructive candidates. Only real terminals enter
# the heap, never all live projectiles. A rejected/stale candidate cannot recycle
# a slot or create a settlement input.
var sim: DB29ProjectileSimulation
var units: ProjectileUnitMotion
var end: float
var heap: Array[Dictionary] = []
var failure_reason := ""
var _revisions: Dictionary = {}
var _targets: Dictionary = {}
var _target_by_slot: Dictionary = {}
var _active_positions: Dictionary = {}
var _path_cells: Dictionary = {}
var _cells_by_slot: Dictionary = {}

func begin(value: DB29ProjectileSimulation,motion: ProjectileUnitMotion) -> void:
	sim = value
	units = motion
	end = sim.time_seconds+GravityBallistics.STEP_SECONDS
	for position: int in sim.active_slots.size():
		_active_positions[sim.active_slots[position]] = position
		_predict(sim.active_slots[position])

func spawn(event: Dictionary) -> Dictionary:
	if not sim._valid(event,end) or sim.active_ids.has(event.event_id) or event.emission_order <= sim.last_order:
		failure_reason = "invalid_emission_batch"
		return {}
	var index: int
	if sim.free_slots.is_empty():
		index = sim.slots.size()
		sim.slots.append({})
		sim.generations.append(0)
	else:
		index = sim.free_slots.pop_back()
		sim.profile.reuses += 1
	sim.generations[index] += 1
	var source := {"event_id":event.event_id,"emission_order":event.emission_order,
		"unit_id":event.unit_id,"owner_player_id":event.owner_player_id,"weapon_instance_id":event.weapon_instance_id}
	sim.slots[index] = {"id":"projectile:"+str(event.event_id),"source":source,"ammo":event.ammo,
		"ammo_values":ProjectileSettlementInput.ammunition(event.ammo),"position":event.position,
		"weapon_values":event.get("weapon_values",{}).duplicate(true),
		"velocity":event.velocity,"time_seconds":float(event.time_seconds),"distance_m":0.0,
		"ignore_house_id":int(event.get("ignore_house_id",0)),"ignore_target_house_id":int(event.get("ignore_target_house_id",0)),
		"generation":sim.generations[index]}
	_active_positions[index] = sim.active_slots.size()
	sim.active_slots.append(index)
	sim.active_ids[event.event_id] = index
	sim.last_order = event.emission_order
	sim.profile.spawned += 1
	var result := sim._event(sim.slots[index],"spawn")
	_predict(index)
	return result

func _predict(index: int) -> void:
	if not failure_reason.is_empty(): return
	_unwatch(index)
	_revisions[index] = int(_revisions.get(index,0))+1
	var state: Dictionary = sim.slots[index]
	var duration := clampf(end-float(state.time_seconds),0.0,GravityBallistics.STEP_SECONDS)
	var motion := GravityBallistics.segment(state.position,state.velocity,duration)
	_unindex(index)
	var path := ProjectileUnitMotion._covered(AABB(state.position,Vector3.ZERO).expand(motion.position))
	_cells_by_slot[index] = path
	for cell: Vector3i in path:
		if not _path_cells.has(cell): _path_cells[cell] = {}
		_path_cells[cell][index] = true
	var hit := {} if duration == 0.0 else sim.collision.static_point_sweep(state.position,motion.position,
		sim.collision.exclusions(int(state.source.unit_id),[state.ignore_house_id,state.ignore_target_house_id]),duration)
	if not hit.has("failure") and units != null and duration > 0.0:
		var unit_hit := units.sweep(state.position,motion.position,float(state.time_seconds),duration,int(state.source.unit_id),float(hit.get("fraction",1.0)),state.get("hit_units",{}))
		if unit_hit.has("failure"): hit = unit_hit
		elif not unit_hit.is_empty() and (hit.is_empty() or float(unit_hit.fraction)*duration < float(hit.fraction)*duration-ProjectileUnitMotion.TIME_TOLERANCE): hit = unit_hit
	if hit.has("failure"):
		failure_reason = str(hit.failure)
		return
	var impact := not hit.is_empty()
	var exit_at := sim._exit_fraction(state.position,motion.position)
	var exited := is_finite(exit_at) and (not impact or exit_at*duration < float(hit.fraction)*duration-ProjectileUnitMotion.TIME_TOLERANCE)
	if not impact and not exited: return
	var elapsed := duration*exit_at if exited else duration*float(hit.fraction)
	var row := {"index":index,"revision":_revisions[index],"generation":state.generation,
		"time_seconds":state.time_seconds+elapsed,"unit_id":state.source.unit_id,
		"weapon_instance_id":state.source.weapon_instance_id,"source_event_id":state.source.event_id,
		"terminal":true,"hit":hit,"exited":exited}
	var target: int = 0 if exited else int(hit.get("unit_id",0))
	if target > 0:
		if not _targets.has(target): _targets[target] = {}
		_targets[target][index] = true
		_target_by_slot[index] = target
	_push(row)

func peek() -> Dictionary:
	while not heap.is_empty():
		var row: Dictionary = heap[0]
		if sim.slots[row.index].is_empty() or sim.slots[row.index].generation != row.generation or _revisions.get(row.index) != row.revision:
			_pop()
		else: return row
	return {}

func preview() -> Dictionary:
	var candidate := peek()
	if candidate.is_empty(): return {}
	var state: Dictionary = sim.slots[candidate.index]
	var projected := state.duplicate()
	var duration := clampf(float(candidate.time_seconds)-float(state.time_seconds),0.0,GravityBallistics.STEP_SECONDS)
	var motion := GravityBallistics.segment(state.position,state.velocity,duration)
	projected.position = motion.position
	projected.velocity = motion.velocity
	projected.distance_m = state.distance_m+motion.distance
	projected.time_seconds = candidate.time_seconds
	var event := sim._event(projected,"battlefield_exit" if candidate.exited else "impact")
	if not candidate.exited:
		var hit: Dictionary = candidate.hit
		event.merge({"point":hit.point,"normal":hit.normal,"object_id":hit.object_id,
			"object_category":hit.get("object_category",""),"hit_unit_id":hit.get("unit_id",0),"hit_unit_type":hit.get("unit_type",-1)},true)
	var input := ProjectileSettlementInput.terminal(event,state.ammo_values,state.weapon_values)
	if sim.overpenetration_enabled:
		input.impact_sequence = state.get("impact_sequence",0)
		input.penetration_loss = state.get("penetration_loss",0.0)
	return {"event":event,"input":input}

func commit(continuation: Dictionary = {}) -> Dictionary:
	var candidate := peek()
	if candidate.is_empty(): return {}
	var result := preview()
	_pop()
	var state: Dictionary = sim.slots[candidate.index]
	if continuation.get("continues",false):
		_advance(state,float(candidate.time_seconds))
		state.penetration_loss = continuation.penetration_loss_next
		state.impact_sequence = int(state.get("impact_sequence",0))+1
		if not state.has("hit_units"): state.hit_units = {}
		state.hit_units[int(candidate.hit.unit_id)] = true
		result.continues = true
		sim.profile.impacts += 1
		_predict(candidate.index)
		return result
	sim.active_ids.erase(state.source.event_id)
	var active_index: int = _active_positions[candidate.index]
	sim.active_slots[active_index] = sim.active_slots.back()
	_active_positions[sim.active_slots[active_index]] = active_index
	sim.active_slots.pop_back()
	_active_positions.erase(candidate.index)
	_unwatch(candidate.index)
	_unindex(candidate.index)
	sim.slots[candidate.index] = {}
	sim.free_slots.append(candidate.index)
	if candidate.exited: sim.profile.exits += 1
	else: sim.profile.impacts += 1
	return result

func _unwatch(index: int) -> void:
	if not _target_by_slot.has(index): return
	var target: int = _target_by_slot[index]
	if _targets.has(target):
		_targets[target].erase(index)
		if _targets[target].is_empty(): _targets.erase(target)
	_target_by_slot.erase(index)

func _unindex(index: int) -> void:
	for cell: Vector3i in _cells_by_slot.get(index,[]):
		_path_cells[cell].erase(index)
		if _path_cells[cell].is_empty(): _path_cells.erase(cell)
	_cells_by_slot.erase(index)

func invalidate_changed(ids: Array,at: float) -> void:
	var affected := {}
	for id: int in ids:
		for index: int in _targets.get(id,{}): affected[index] = true
		if units != null and units.records.has(id):
			for cell: Vector3i in ProjectileUnitMotion._covered(units.records[id].bounds):
				for index: int in _path_cells.get(cell,{}): affected[index] = true
	for index: int in affected:
		if sim.slots[index].is_empty(): continue
		_advance(sim.slots[index],at)
		_predict(index)

# Death/removal invalidation touches candidates that actually targeted that unit.
# No whole-world or surviving-projectile sort; their valid predictions remain.
func invalidate_removed(ids: Array,at: float) -> void:
	var affected := {}
	for id: int in ids:
		if units != null: units.remove_unit(id)
		for index: int in _targets.get(id,{}): affected[index] = true
		_targets.erase(id)
	for index: int in affected:
		if sim.slots[index].is_empty(): continue
		_advance(sim.slots[index],at)
		_predict(index)

func finish() -> void:
	for index: int in sim.active_slots:
		_advance(sim.slots[index],end)
	sim.time_seconds = end

func _advance(state: Dictionary,at: float) -> void:
	# Same complete-step clamping as DB29ProjectileSimulation: repeated absolute
	# timestamps can subtract to h+ulp, which is not a legal longer segment.
	var duration := clampf(at-float(state.time_seconds),0.0,GravityBallistics.STEP_SECONDS)
	var motion := GravityBallistics.segment(state.position,state.velocity,duration)
	state.position = motion.position
	state.velocity = motion.velocity
	state.distance_m += motion.distance
	state.time_seconds = at
	sim.profile.updates += 1

func _push(row: Dictionary) -> void:
	heap.append(row)
	var index := heap.size()-1
	while index > 0:
		var parent := (index-1)/2
		if not CombatEventOrder.before(heap[index],heap[parent]): break
		var swap := heap[parent]
		heap[parent] = heap[index]
		heap[index] = swap
		index = parent

func _pop() -> Dictionary:
	var result: Dictionary = heap[0]
	var tail: Dictionary = heap.pop_back()
	if heap.is_empty(): return result
	heap[0] = tail
	var index := 0
	while index*2+1 < heap.size():
		var child := index*2+1
		if child+1 < heap.size() and CombatEventOrder.before(heap[child+1],heap[child]): child += 1
		if not CombatEventOrder.before(heap[child],heap[index]): break
		var swap := heap[index]
		heap[index] = heap[child]
		heap[child] = swap
		index = child
	return result
