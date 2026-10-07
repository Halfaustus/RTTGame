class_name InfantrySuppressionSettlement
extends RefCounted

# Internal event adapter. Caller coordinates movement/aim/fire resampling.
# Active combat coordinates Q with remaining movement/aim/fire resampling.
var states: Dictionary = {}
var records: Dictionary = {}
var last_time := 0.0

func register_unit(id: int,count: int,s: float,wait: float,fraction: float,at: float = 0.0) -> bool:
	if id <= 0 or states.has(id): return false
	var state := InfantrySuppressionState.new()
	if not state.configure(count,s,wait,fraction,at): return false
	states[id] = state
	return true

# Membership is the surviving count AFTER this attack's damage has committed.
# Prevalidate the whole batch before touching any state. One row per squad.
func commit(event_id: String,at: float,inputs: Array[Dictionary],survivors: Dictionary) -> Dictionary:
	if event_id.is_empty() or records.has(event_id): return {"ok":false,"reason":"suppression_event_duplicate_or_missing"}
	if not InfantrySuppressionState.finite_nonnegative(at) or at < last_time: return {"ok":false,"reason":"suppression_time_invalid"}
	var touched := {}
	for id: Variant in survivors:
		if not id is int or not states.has(id): return {"ok":false,"reason":"suppression_unit_unregistered"}
		var state: InfantrySuppressionState = states[id]
		if not survivors[id] is int or survivors[id] < 0 or survivors[id] > state.configured_count or at < state.time_seconds: return {"ok":false,"reason":"suppression_population_invalid"}
		touched[id] = 0.0
	var seen := {}
	for row: Dictionary in inputs:
		var id: Variant = row.get("unit_id")
		if not id is int or not touched.has(id) or seen.has(id): return {"ok":false,"reason":"suppression_squad_duplicate_or_missing"}
		var amount: Variant = row.get("amount")
		if not (amount is float or amount is int) or not InfantrySuppressionState.finite_nonnegative(float(amount)): return {"ok":false,"reason":"suppression_amount_invalid"}
		seen[id] = true
		touched[id] = float(amount)
	var results: Array[Dictionary] = []
	for id: int in touched:
		var state: InfantrySuppressionState = states[id]
		var before := state.q
		state.advance_to(at)
		state.set_alive_count(survivors[id])
		if seen.has(id) and state.alive_count > 0: state.effective_event(touched[id])
		results.append({"unit_id":id,"event_id":event_id,"time_seconds":at,"q_before":before,"q_after":state.q,
			"alive_count":state.alive_count,"personnel_state":state.personnel_state(),"modifiers":state.modifiers()})
	last_time = at
	records[event_id] = results.duplicate(true)
	return {"ok":true,"results":results}
