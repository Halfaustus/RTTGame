class_name OrderedFireStep
extends RefCounted

# Transient per-step due indices; RuntimeWeaponInstance retains all timer/stock
# authority. Existing scheduler helpers still own eligibility, solve and debit.
var fire: FireSimulation
var aiming: AimingSimulation
var frame: FiringFrame
var start: float
var end: float
var channels: Array[Dictionary] = []
var heap: Array[Dictionary] = []
var failure_reason := ""
var affected_channels: Dictionary = {}

func begin(value: FireSimulation,aim: AimingSimulation,sample: FiringFrame) -> void:
	fire = value
	aiming = aim
	frame = sample
	start = fire.time_seconds
	end = start+GravityBallistics.STEP_SECONDS
	fire.last_tick += 1
	for unit: UnitState in aiming.units.values():
		for weapon: RuntimeWeaponInstance in unit.runtime_weapons:
			var entry := {"weapon":weapon,"cursor":start,"revision":0}
			channels.append(entry)
			_watch(unit.unit_id,entry)
			if weapon.target != null: _watch(weapon.target.unit_id,entry)
			weapon.fire_state.can_fire = false
			_schedule(entry,start,true)

func _schedule(entry: Dictionary,at: float,initial: bool = false) -> void:
	entry.revision += 1
	var weapon: RuntimeWeaponInstance = entry.weapon
	weapon.fire_state.reason = FixedFireScheduler._eligibility(weapon,aiming,frame,at,true)
	if weapon.fire_state.reason != "eligible": return
	var wait := FixedFireScheduler._wait(weapon,aiming.inputs.get(weapon.owner_state().unit_id,{}))
	if frame != null: wait = maxf(wait,float(frame.weapons[weapon.instance_id].ready)-at)
	if not is_finite(wait) or (not initial and wait <= FireSimulation.TIME_EPSILON):
		weapon.fire_state.reason = "fire_configuration_missing"
		return
	var due := at+wait
	if due > end+FireSimulation.TIME_EPSILON: return
	var row := {"entry":entry,"revision":entry.revision,"time_seconds":minf(due,end),
		"unit_id":weapon.owner_state().unit_id,"weapon_instance_id":weapon.instance_id,
		"source_event_id":"%s:%s" % [weapon.instance_id,weapon.fire_state.emission_count+1],"terminal":false}
	_push(row)

func peek() -> Dictionary:
	while not heap.is_empty() and heap[0].revision != heap[0].entry.revision: _pop()
	return {} if heap.is_empty() else heap[0]

func commit() -> Dictionary:
	var candidate := peek()
	if candidate.is_empty(): return {}
	_pop()
	var entry: Dictionary = candidate.entry
	var at: float = candidate.time_seconds
	FixedFireScheduler._advance(fire,entry,at,aiming)
	var weapon: RuntimeWeaponInstance = entry.weapon
	# A removed unit cannot emit even if a weak owner reference is still alive.
	if not aiming.units.has(candidate.unit_id):
		weapon.fire_state.reason = "owner_invalid"
		return {}
	var event := FixedFireScheduler._emit(fire,weapon,at,aiming,frame)
	if not event.is_empty(): _schedule(entry,at)
	return event

# Consumers explicitly prepare the affected identities before mutating state.
# Advance old-rate loading to the event boundary, then reschedule after commit.
func advance_affected(ids: Array,at: float) -> void:
	for entry: Dictionary in _affected(ids): FixedFireScheduler._advance(fire,entry,at,aiming)

func invalidate(ids: Array,at: float) -> void:
	for entry: Dictionary in _affected(ids):
		var weapon: RuntimeWeaponInstance = entry.weapon
		var owner := weapon.owner_state()
		if owner == null: continue
		if ids.has(owner.unit_id) or (weapon.target != null and ids.has(weapon.target.unit_id)):
			entry.revision += 1
			if not aiming.units.has(owner.unit_id):
				weapon.fire_state.reason = "owner_invalid"
				continue
			_schedule(entry,at,true)

func _watch(id: int,entry: Dictionary) -> void:
	if not affected_channels.has(id): affected_channels[id] = {}
	affected_channels[id][entry.weapon.instance_id] = entry

func _affected(ids: Array) -> Array[Dictionary]:
	var selected := {}
	for id: int in ids: selected.merge(affected_channels.get(id,{}),true)
	var result: Array[Dictionary] = []
	result.assign(selected.values())
	return result

func finish() -> void:
	for entry: Dictionary in channels:
		FixedFireScheduler._advance(fire,entry,end,aiming)
		var state: WeaponFireState = entry.weapon.fire_state
		if state.reason == "eligible":
			state.reason = "loading" if state.loading else "interval"
			state.phase = WeaponFireState.Phase.LOADING if state.loading else WeaponFireState.Phase.INTERVAL
	fire.time_seconds = end

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
