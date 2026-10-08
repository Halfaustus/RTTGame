class_name CombatOutcomeLedger
extends RefCounted

# Match-local, server-only identities survive unit retirement and disconnects.
# Neither identities nor death records are public projectile/replay payloads.
signal statistics_changed(player_id: int)
var identities: Dictionary = {}
var deaths: Dictionary = {}
var totals: Dictionary = {}
var failure_reason := ""
var _next_death_sequence := 1

func register_unit(unit: UnitState, value_points: Variant) -> bool:
	if unit == null or unit.unit_id <= 0: return false
	if value_points != null and not DeploymentEconomy.valid_score(value_points): return false
	var identity := {"unit_id":unit.unit_id,"player_id":unit.owner_player_id,
		"team_id":unit.team_id,"unit_kind":unit.unit_type(),"value_points":value_points}
	if identities.has(unit.unit_id): return identities[unit.unit_id] == identity
	identities[unit.unit_id] = identity
	return true

func commit_damage(result: Dictionary) -> bool:
	if not result.get("unit_died",false): return true
	var id: int = result.get("unit_id",0)
	if deaths.has(id): return true # One whole-unit death, including explosion batches.
	var source_id: int = result.get("source_unit_id",0)
	if not identities.has(id) or not identities.has(source_id):
		failure_reason = "combat_identity_missing"
		return false
	var victim: Dictionary = identities[id]
	var killer: Dictionary = identities[source_id]
	if killer.player_id != result.get("source_player_id",-1):
		failure_reason = "combat_source_identity_mismatch"
		return false
	var friendly: bool = victim.team_id == killer.team_id
	deaths[id] = {"unit_id":id,"player_id":victim.player_id,"team_id":victim.team_id,
		"value_points":victim.value_points,"killer_unit_id":source_id,"killer_player_id":killer.player_id,
		"unit_kind":victim.unit_kind,"killer_unit_kind":killer.unit_kind,
		"friendly_fire":friendly,"time_seconds":result.time_seconds,"sequence":_next_death_sequence,
		"source_event_id":result.source_event_id}
	_next_death_sequence += 1
	_add(victim.player_id,"death_value",victim.value_points)
	if not friendly: _add(killer.player_id,"kill_value",victim.value_points)
	return true

func _add(player_id: int, field: String, value: Variant) -> void:
	if not totals.has(player_id): totals[player_id] = {"kill_value":0,"death_value":0,"unknown_kills":0,"unknown_deaths":0}
	if value == null: totals[player_id]["unknown_kills" if field == "kill_value" else "unknown_deaths"] += 1
	else: totals[player_id][field] += int(value)
	statistics_changed.emit(player_id)

func project_player(player_id: int) -> Dictionary:
	var total: Dictionary = totals.get(player_id,{"kill_value":0,"death_value":0,"unknown_kills":0,"unknown_deaths":0})
	var kills_known: bool = total.unknown_kills == 0
	var deaths_known: bool = total.unknown_deaths == 0
	var ready: bool = kills_known and deaths_known
	return {"player_id":player_id,"kill_value":total.kill_value if kills_known else null,
		"death_value":total.death_value if deaths_known else null,
		"configured":ready,"value_kd":float(total.kill_value)/total.death_value if ready and total.death_value > 0 else null,
		"display_kd":"未配置" if not ready else "无损" if total.death_value == 0 else "%.2f" % (float(total.kill_value)/total.death_value)}

func project_records(player_id: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for death: Dictionary in deaths.values():
		if death.player_id != player_id and death.killer_player_id != player_id: continue
		result.append({"unit_id":death.unit_id,"player_id":death.player_id,"unit_kind":death.unit_kind,
			"killer_unit_id":death.killer_unit_id,"killer_player_id":death.killer_player_id,
			"killer_unit_kind":death.killer_unit_kind,"value_points":death.value_points,
			"friendly_fire":death.friendly_fire,"time_seconds":death.time_seconds,
			"sequence":death.sequence})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.time_seconds != b.time_seconds: return a.time_seconds < b.time_seconds
		return a.sequence < b.sequence)
	return result
