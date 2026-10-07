class_name DB29CombatTimeline
extends RefCounted

# Shared authoritative fixed-step chain for isolated tests and active servers.
# Movement endpoints and FiringFrame provide within-step collision/aim sampling.
var fire := FireSimulation.new()
var projectiles := DB29ProjectileSimulation.new()
var halted := false
var failure_reason := ""
var clock := FixedStepClock.new()
var callback_results: Array[Dictionary] = []
var settlement_inbox := ProjectileSettlementInbox.new()
# Optional SERVER-ONLY future consumer. Preparation declares touched units and
# validates without mutation; commit runs at the actual terminal time, never at
# the end of the firing batch. A has no production damage consumer.
var settlement_prepare: Callable
var settlement_commit: Callable
var direct_hit_enabled := false
var overpenetration_enabled := false
var direct_hits := DirectHitSettlement.new()
var suppression_enabled := false
var suppression_runtime: InfantrySuppressionRuntime
var modules_enabled := false
var module_runtime: VehicleModuleRuntime

func _init() -> void:
	settlement_inbox.configure({"match_id":"test_only:"+Crypto.new().generate_random_bytes(16).hex_encode(),
		"map_id":"test_only:isolated_geometry","rules_id":ConfirmedDataValidator.RULES_ID,
		"data_version":ConfirmedDataValidator.DATA_VERSION,"data_sha256":FileAccess.get_sha256(ConfirmedGameData.PATH)})

func configure_settlement_context(context: Dictionary) -> bool:
	if fire.time_seconds != 0.0 or not projectiles.active_slots.is_empty(): return false
	return settlement_inbox.configure(context)

# Callback debt is shared by movement, firing and projectile consumption.
# No independent projectile clock and no capped/discarded emission list.
func advance(elapsed: float,movement: MovementSimulation,aiming: AimingSimulation) -> Array[Dictionary]:
	callback_results.clear()
	clock.advance(elapsed,func() -> bool:
		var result := step_movement(movement,aiming)
		callback_results.append(result)
		return not halted and failure_reason.is_empty())
	if not clock.failure_reason.is_empty() and failure_reason.is_empty(): failure_reason = clock.failure_reason
	return callback_results.duplicate()

# Own the sampling order for one exact fixed step, without choosing a backlog
# policy or replacing the active NetworkManager's existing 60Hz movement loop.
func step_movement(movement: MovementSimulation,aiming: AimingSimulation) -> Dictionary:
	if halted: return {"emissions":[],"events":[],"changed":{}}
	failure_reason = ""
	if fire.execution_mode == "legacy" or fire.time_seconds != projectiles.time_seconds:
		halted = true
		failure_reason = "combat_clock_mismatch"
		return {"emissions":[],"events":[],"changed":{}}
	# The movement sample and combat must refer to the same authoritative units.
	if not movement.matches_units(aiming.units):
		failure_reason = "movement_combat_units_mismatch"
		return {"emissions":[],"events":[],"changed":{}}
	var frame := FiringFrame.new()
	if modules_enabled:
		if module_runtime == null: module_runtime = VehicleModuleRuntime.new()
		module_runtime.begin(aiming)
	if suppression_enabled:
		if suppression_runtime == null: suppression_runtime = InfantrySuppressionRuntime.new()
		if not suppression_runtime.begin(aiming,fire.time_seconds): return _fail(suppression_runtime.failure_reason)
	frame.movement = movement
	frame.begin(fire.time_seconds,aiming,direct_hit_enabled)
	movement.attack_facing_requests = aiming.hull_requests()
	# Start-of-step eligibility owns aim progress; never backdate newly eligible
	# step-end targets. Turning/aim/loading remain parallel, independent states.
	aiming.advance(GravityBallistics.STEP_SECONDS)
	var sample := movement.advance_sampled(fire.time_seconds)
	if sample.reason != "":
		halted = true
		failure_reason = sample.reason
		return {"emissions":[],"events":[],"changed":sample.changed,"motion":sample.motion}
	# Values are observed average step translation, not instantaneous velocity at
	# corners or stops. Current firing refuses nonzero target motion explicitly.
	aiming.target_velocities = sample.velocities
	frame.finish(aiming,sample.motion)
	var result := step(aiming,sample.motion,frame)
	for hit: Dictionary in result.get("damage_results",[]):
		if hit.unit_died: movement._clear_move(hit.unit_id)
		result.get("changed",sample.changed)[hit.unit_id] = aiming.units[hit.unit_id].position
	result.changed = sample.changed
	for item: Dictionary in result.get("module_results",[]):
		result.changed[item.unit_id] = aiming.units[item.unit_id].position
	for item: Dictionary in result.get("suppression_results",[]):
		result.changed[item.unit_id] = aiming.units[item.unit_id].position
	result.motion = sample.motion
	if not failure_reason.is_empty(): halted = true
	return result

func step(aiming: AimingSimulation,units: ProjectileUnitMotion = null,frame: FiringFrame = null) -> Dictionary:
	if halted: return {"emissions":[],"events":[]}
	failure_reason = ""
	if modules_enabled:
		if not direct_hit_enabled: return _fail("modules_require_impact_consumer")
		if module_runtime == null: module_runtime = VehicleModuleRuntime.new()
		module_runtime.begin(aiming)
	if suppression_enabled:
		if not direct_hit_enabled: return _fail("suppression_requires_impact_consumer")
		if suppression_runtime == null: suppression_runtime = InfantrySuppressionRuntime.new()
		if not suppression_runtime.begin(aiming,fire.time_seconds): return _fail(suppression_runtime.failure_reason)
	if fire.execution_mode == "legacy" or fire.time_seconds != projectiles.time_seconds:
		halted = true
		failure_reason = "combat_clock_mismatch"
		return {"emissions":[],"events":[]}
	if units != null and (not units.ready or absf(units.time_seconds-fire.time_seconds) > ProjectileUnitMotion.TIME_TOLERANCE):
		failure_reason = "unit_motion_frame_invalid"
		return {"emissions":[],"events":[]} # Validate before firing/debit.
	if projectiles.halted or settlement_prepare.is_valid() != settlement_commit.is_valid():
		return _fail("settlement_consumer_invalid")
	var consumer_prepare := settlement_prepare
	var consumer_commit := settlement_commit
	var impact_frame := frame
	if direct_hit_enabled:
		if consumer_prepare.is_valid(): return _fail("settlement_consumer_conflict")
		if impact_frame == null:
			impact_frame = FiringFrame.new()
			impact_frame.begin(fire.time_seconds,aiming,true)
			impact_frame.finish(aiming,units)
		if units == null:
			units = ProjectileUnitMotion.new()
			var stationary := ProjectileUnitMotion.capture(aiming.units)
			if not units.configure(fire.time_seconds,stationary,stationary): return _fail(units.failure_reason)
			impact_frame.motion = units
		direct_hits.begin(aiming,impact_frame)
		impact_frame.overpenetration_enabled = overpenetration_enabled
		direct_hits.suppression_enabled = suppression_enabled
		direct_hits.overpenetration_enabled = overpenetration_enabled
		consumer_prepare = direct_hits.prepare
		consumer_commit = direct_hits.commit
	var firing := OrderedFireStep.new()
	var flight := OrderedProjectileStep.new()
	projectiles.overpenetration_enabled = overpenetration_enabled and direct_hit_enabled
	flight.begin(projectiles,units)
	if not flight.failure_reason.is_empty(): return _fail(flight.failure_reason)
	fire.execution_mode = "fixed"
	firing.begin(fire,aiming,impact_frame if direct_hit_enabled else frame)
	var emitted: Array[Dictionary] = []
	var events: Array[Dictionary] = []
	var settlements: Array[Dictionary] = []
	var result := {"emissions":emitted,"events":events,"settlements":settlements,"damage_results":direct_hits.results if direct_hit_enabled else [],"suppression_inputs":direct_hits.suppression_inputs if direct_hit_enabled else []}
	result.suppression_results = []
	result.module_results = []
	while true:
		var due := firing.peek()
		var terminal := flight.peek()
		var recovery := suppression_runtime.peek(flight.end) if suppression_enabled else {}
		if not recovery.is_empty() and (due.is_empty() or recovery.time_seconds <= due.time_seconds) and (terminal.is_empty() or recovery.time_seconds <= terminal.time_seconds):
			var id: int = recovery.unit_id
			var at: float = recovery.time_seconds
			var old: Dictionary = aiming.inputs.get(id,{}).duplicate(true)
			firing.advance_affected([id],at)
			suppression_runtime.recover(aiming)
			if old != aiming.inputs.get(id,{}):
				var changed := impact_frame.refresh_casualty(aiming.units[id],at,aiming,old,true)
				if not units.replace_unit(id,at,changed.before,changed.after): return _fail("suppression_recovery_motion_invalid",result)
				flight.invalidate_changed([id],at)
				firing.invalidate([id],at)
				if not flight.failure_reason.is_empty(): return _fail(flight.failure_reason,result)
			result.suppression_results.append({"unit_id":id,"time_seconds":at,"kind":"recovery"})
			continue
		if due.is_empty() and terminal.is_empty(): break
		if terminal.is_empty() or (not due.is_empty() and CombatEventOrder.before(due,terminal)):
			var emission := firing.commit()
			if emission.is_empty(): continue
			result.emissions.append(emission)
			var spawn := flight.spawn(emission)
			if spawn.is_empty() or not flight.failure_reason.is_empty():
				return _fail(flight.failure_reason,result)
			result.events.append(spawn)
		else:
			var prepared := flight.preview()
			var input: Dictionary = prepared.input
			var affected: Array = []
			var impact_plan := {}
			if consumer_prepare.is_valid():
				var plan: Variant = consumer_prepare.call(input.duplicate(true))
				if not plan is Dictionary or plan.get("ok") != true or not plan.get("affected_unit_ids") is Array:
					return _fail("settlement_prepare_failed",result)
				affected = plan.affected_unit_ids
				impact_plan = plan
				for id: Variant in affected:
					if not id is int or id <= 0: return _fail("settlement_affected_identity_invalid",result)
			if modules_enabled and not module_runtime.prepare(input,direct_hits.plans.get(ProjectileSettlementInput.key(input),{})):
				return _fail(module_runtime.failure_reason,result)
			if not settlement_inbox.accept_batch([input]): return _fail(settlement_inbox.failure_reason,result)
			if suppression_enabled and not suppression_runtime.validate(affected,float(input.time_seconds)): return _fail("suppression_event_time_invalid",result)
			firing.advance_affected(affected,float(input.time_seconds))
			var submitted := flight.commit(impact_plan)
			if not submitted.get("continues",false): result.events.append(submitted.event)
			if consumer_commit.is_valid():
				var poses := {}
				var old_inputs := {}
				for id: int in affected:
					if aiming.units.has(id): poses.merge(ProjectileUnitMotion.capture({id:aiming.units[id]}))
					old_inputs[id] = aiming.inputs.get(id,{}).duplicate(true)
				var outcome: Variant = consumer_commit.call(input.duplicate(true))
				if not outcome is Dictionary or outcome.get("ok") != true:
					return _fail("settlement_commit_failed",result)
				var removed: Array = []
				var refreshed: Array = []
				var rate_changed: Array = []
				if modules_enabled:
					var modules := module_runtime.commit(input,aiming)
					if not modules.ok: return _fail(modules.reason,result)
					result.module_results.append_array(modules.results)
					for module_result: Dictionary in modules.results:
						if module_result.levels != module_result.before_levels: rate_changed.append(module_result.unit_id)
				if suppression_enabled:
					var rows: Array[Dictionary] = []
					for row: Dictionary in direct_hits.suppression_inputs:
						if row.get("emission_order",input.emission_order) == input.emission_order and affected.has(row.unit_id): rows.append(row)
					var suppressed := suppression_runtime.commit(input,affected,rows,aiming)
					if not suppressed.ok: return _fail(str(suppressed.reason),result)
					result.suppression_results.append_array(suppressed.results)
				for id: int in affected:
					if aiming.inputs.get(id,{}) != old_inputs[id] and not rate_changed.has(id): rate_changed.append(id)
				if direct_hit_enabled:
					var rebuild: Array = outcome.get("casualty_unit_ids",[]).duplicate()
					for id: int in rate_changed:
						if not rebuild.has(id): rebuild.append(id)
					for id: int in rebuild:
						var changed := impact_frame.refresh_casualty(aiming.units[id],float(input.time_seconds),aiming,old_inputs[id],rate_changed.has(id))
						if not units.replace_unit(id,float(input.time_seconds),changed.before,changed.after): return _fail("casualty_motion_invalid",result)
						refreshed.append(id)
				for id: int in affected:
					if not aiming.units.has(id) or aiming.units[id].health <= 0:
						removed.append(id)
					else:
						var next := ProjectileUnitMotion.capture({id:aiming.units[id]})
						if next.get(id) != poses.get(id) and not refreshed.has(id): return _fail("settlement_motion_resampling_required",result)
						if aiming.inputs.get(id,{}) != old_inputs[id] and not refreshed.has(id): return _fail("settlement_motion_resampling_required",result)
				# State affecting pre-sampled movement/aim needs a new integration in
				# B/D. Explicit refusal is safer than silently using stale endpoints.
				if outcome.get("requires_resampling",false): return _fail("settlement_motion_resampling_required",result)
				flight.invalidate_removed(removed,float(input.time_seconds))
				flight.invalidate_changed(refreshed,float(input.time_seconds))
				firing.invalidate(affected,float(input.time_seconds))
				if not flight.failure_reason.is_empty(): return _fail(flight.failure_reason,result)
			result.settlements.append_array(settlement_inbox.take_pending())
	firing.finish()
	flight.finish()
	if suppression_enabled: suppression_runtime.finish(fire.time_seconds)
	return result

func _fail(reason: String,result: Dictionary = {}) -> Dictionary:
	failure_reason = reason if not reason.is_empty() else "settlement_step_failed"
	halted = true
	projectiles.halted = true
	projectiles.failure_reason = failure_reason
	if result.is_empty(): return {"emissions":[],"events":[],"settlements":[]}
	result.failure_reason = failure_reason
	# Accepted-but-unconfirmed inputs are quarantined on permanent halt. They are
	# neither returned as successful settlements nor silently redelivered later.
	result.failed_settlement_inputs = settlement_inbox.take_pending()
	return result
