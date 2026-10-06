class_name FixedStepClock
extends RefCounted

# C-authorized technical budget, independent of shot rate and unit configuration.
const MAX_STEPS_PER_CALLBACK := 8
var pending_seconds := 0.0
var completed_steps := 0
var failure_reason := ""

func advance(elapsed: float, step_callback: Callable) -> int:
	failure_reason = ""
	if not is_finite(elapsed) or elapsed < 0.0 or not step_callback.is_valid():
		failure_reason = "invalid_clock_input"
		return 0
	if not is_finite(pending_seconds+elapsed):
		failure_reason = "invalid_clock_input"
		return 0
	pending_seconds += elapsed
	var count := 0
	while pending_seconds+FireSimulation.TIME_EPSILON >= GravityBallistics.STEP_SECONDS and count < MAX_STEPS_PER_CALLBACK:
		# A failed authoritative step locks its coordinator; never discard backlog.
		if not step_callback.call():
			failure_reason = "authoritative_step_failed"
			break
		pending_seconds = maxf(0.0,pending_seconds-GravityBallistics.STEP_SECONDS)
		completed_steps += 1
		count += 1
	return count
