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
	frame.begin(fire.time_seconds,aiming)
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
	result.changed = sample.changed
	result.motion = sample.motion
	if not failure_reason.is_empty(): halted = true
	return result

func step(aiming: AimingSimulation,units: ProjectileUnitMotion = null,frame: FiringFrame = null) -> Dictionary:
	if halted: return {"emissions":[],"events":[]}
	failure_reason = ""
	if fire.execution_mode == "legacy" or fire.time_seconds != projectiles.time_seconds:
		halted = true
		failure_reason = "combat_clock_mismatch"
		return {"emissions":[],"events":[]}
	if units != null and (not units.ready or absf(units.time_seconds-fire.time_seconds) > ProjectileUnitMotion.TIME_TOLERANCE):
		failure_reason = "unit_motion_frame_invalid"
		return {"emissions":[],"events":[]} # Validate before firing/debit.
	var emissions := fire.advance_fixed(aiming,frame)
	var events := projectiles.step(emissions,units)
	if not projectiles.failure_reason.is_empty():
		halted = true
		failure_reason = projectiles.failure_reason
	return {"emissions":emissions,"events":events}
