class_name InfantrySuppressionRuntime
extends RefCounted

# Server-only recovery heap. Only squads with Q>0 own pending boundaries.
var settlement := InfantrySuppressionSettlement.new()
var base_inputs: Dictionary = {}
var active: Dictionary = {}
var revisions: Dictionary = {}
var heap: Array[Dictionary] = []
var failure_reason := ""
var data := ConfirmedGameData.new()
var allowance := NAN
var wait := NAN
var fraction := NAN

func _init() -> void:
	allowance = data.number(data.record("Parameters","每人压制额度 s"),"Value")
	wait = data.number(data.record("Parameters","压制恢复等待"),"Value")
	var value: Variant = data.record("Parameters","恢复幅度").get("Value")
	if value is String and value.ends_with("%") and value.trim_suffix("%").is_valid_float(): fraction = float(value.trim_suffix("%"))/100.0

func begin(aiming: AimingSimulation,at: float) -> bool:
	for unit: UnitState in aiming.units.values():
		if unit.unit_type() != UnitDefinition.UnitType.INFANTRY or unit.members.is_empty(): continue
		if settlement.states.has(unit.unit_id): continue # Existing squads change only through actual membership/effect events.
		if not settlement.states.has(unit.unit_id):
			if not settlement.register_unit(unit.unit_id,unit.members.size(),allowance,wait,fraction,at):
				failure_reason = "suppression_configuration_missing"
				return false
			unit.suppression = settlement.states[unit.unit_id]
			base_inputs[unit.unit_id] = {}
			for key: String in ["aim_time_multiplier","personnel_load_multiplier","spread_multiplier"]:
				base_inputs[unit.unit_id][key] = aiming.inputs.get(unit.unit_id,{}).get(key,1.0)
		var state: InfantrySuppressionState = settlement.states[unit.unit_id]
		state.set_alive_count(living(unit))
		apply_modifiers(unit,aiming)
	return true

func membership_changed(id: int,at: float,aiming: AimingSimulation,event_id: String) -> Dictionary:
	# Authoritative reinforcement/configuration callers can submit population
	# changes without manufacturing an effective hit or refreshing recovery.
	return commit({"source_event_id":event_id,"time_seconds":at},[id],[],aiming)

static func living(unit: UnitState) -> int:
	var count := 0
	for member: SoldierState in unit.members:
		if member.health > 0: count += 1
	return count

func validate(ids: Array,at: float) -> bool:
	for id: int in ids:
		if settlement.states.has(id) and at < settlement.states[id].time_seconds: return false
	return true

func commit(input: Dictionary,ids: Array,rows: Array[Dictionary],aiming: AimingSimulation) -> Dictionary:
	var survivors := {}
	var applicable: Array[Dictionary] = []
	for id: int in ids:
		if settlement.states.has(id): survivors[id] = living(aiming.units[id])
	for row: Dictionary in rows:
		if survivors.has(row.unit_id): applicable.append(row)
	var outcome := settlement.commit(ProjectileSettlementInput.effect_id(input),float(input.time_seconds),applicable,survivors)
	if not outcome.ok: return outcome
	for id: int in survivors:
		apply_modifiers(aiming.units[id],aiming)
		_schedule(id)
	return outcome

func apply_modifiers(unit: UnitState,aiming: AimingSimulation) -> void:
	var state: InfantrySuppressionState = settlement.states[unit.unit_id]
	var modifiers := state.modifiers(true)
	var inputs: Dictionary = aiming.inputs.get(unit.unit_id,{}).duplicate(true)
	for key: String in base_inputs[unit.unit_id]: inputs[key] = base_inputs[unit.unit_id][key]*modifiers[key]
	inputs.personnel_base_spread = base_inputs[unit.unit_id].spread_multiplier
	aiming.inputs[unit.unit_id] = inputs
	unit.personnel_speed_multiplier = modifiers.movement
	unit.personnel_vision_multiplier = modifiers.vision

func peek(end: float) -> Dictionary:
	while not heap.is_empty() and heap[0].revision != revisions.get(heap[0].unit_id): _pop()
	return {} if heap.is_empty() or heap[0].time_seconds > end else heap[0]

func recover(aiming: AimingSimulation) -> Dictionary:
	var row := _pop()
	var state: InfantrySuppressionState = settlement.states[row.unit_id]
	state.advance_to(row.time_seconds)
	if row.has("target"): state.q = row.target # Exact analytical threshold, no time epsilon.
	apply_modifiers(aiming.units[row.unit_id],aiming)
	_schedule(row.unit_id)
	return row

func finish(at: float) -> void:
	for id: int in active.keys():
		var state: InfantrySuppressionState = settlement.states[id]
		state.advance_to(at)
		if state.q <= 0 or state.alive_count == 0: active.erase(id)

func _schedule(id: int) -> void:
	revisions[id] = int(revisions.get(id,0))+1
	var state: InfantrySuppressionState = settlement.states[id]
	if state.q <= 0 or state.alive_count == 0:
		active.erase(id)
		return
	active[id] = true
	var at := state.next_boundary()
	if not is_finite(at): return
	var row := {"unit_id":id,"time_seconds":at,"revision":revisions[id]}
	if state.time_seconds >= state.last_effective_event+state.recovery_wait:
		row.target = state.alive_count*state.allowance if state.q > state.alive_count*state.allowance else 0.0
	heap.append(row)
	var index := heap.size()-1
	while index > 0:
		var parent := (index-1)/2
		if not _before(heap[index],heap[parent]): break
		var other := heap[parent]
		heap[parent] = heap[index]
		heap[index] = other
		index = parent

static func _before(a: Dictionary,b: Dictionary) -> bool:
	return a.time_seconds < b.time_seconds or (a.time_seconds == b.time_seconds and a.unit_id < b.unit_id)

func _pop() -> Dictionary:
	var row: Dictionary = heap[0]
	var tail: Dictionary = heap.pop_back()
	if heap.is_empty(): return row
	heap[0] = tail
	var index := 0
	while index*2+1 < heap.size():
		var child := index*2+1
		if child+1 < heap.size() and _before(heap[child+1],heap[child]): child += 1
		if not _before(heap[child],heap[index]): break
		var other := heap[index]
		heap[index] = heap[child]
		heap[child] = other
		index = child
	return row
