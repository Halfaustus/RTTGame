class_name GravityBallistics
extends RefCounted

# DB29 section 18 mechanism constants, not weapon configuration.
const GRAVITY := Vector3(0.0, -10.0, 0.0)
const STEP_SECONDS := 1.0 / 30.0
const STEP_VELOCITY := GRAVITY * STEP_SECONDS
const STEP_DISPLACEMENT := GRAVITY * (0.5 * STEP_SECONDS * STEP_SECONDS)

# 0.5G launch policy, not ammunition DATA or a projectile lifetime.
# >1 selects the longer-time branch; 1.04 leaves margin below 20s at 1800m.
const INDIRECT_HIGH_TIME_FACTOR := 1.04
const INDIRECT_MAX_FLIGHT_SECONDS := 20.0

static func indirect(origin: Vector3, target: Vector3, spread: Vector3 = Vector3.ZERO) -> Dictionary:
	if not origin.is_finite() or not target.is_finite() or not spread.is_finite():
		return _failure("invalid_initial_conditions", 1)
	var point := target + spread
	var offset := point - origin
	# |v(t)|² = |offset|²/t² + g*H + g²*t²/4.
	# Its minimum occurs at t²=2*|offset|/g; larger t is the high branch.
	var seconds := INDIRECT_HIGH_TIME_FACTOR * sqrt(2.0 * offset.length() / -GRAVITY.y)
	if not is_finite(seconds) or seconds <= 0.0:
		return _failure("no_positive_flight_time", 1)
	if seconds > INDIRECT_MAX_FLIGHT_SECONDS:
		return _failure("indirect_flight_time_exceeded", 1)
	var velocity := offset / seconds - GRAVITY * (0.5 * seconds)
	if not velocity.is_finite(): return _failure("invalid_initial_conditions", 1)
	return {"valid":true,"reason":"eligible","velocity":velocity,"seconds":seconds,"point":point,"solves":1}

# Call at actual emission time. The caller samples spread once and supplies
# that same world-space offset; this solver never samples or changes it.
static func direct(origin: Vector3, target: Vector3, target_velocity: Vector3, speed: float, spread: Vector3 = Vector3.ZERO) -> Dictionary:
	if not target_velocity.is_finite() or not spread.is_finite():
		return _failure("invalid_initial_conditions", 0)
	var point := target + spread
	var result := low(origin, point, speed)
	result.solves = 1
	if not result.valid or target_velocity == Vector3.ZERO:
		return result
	for iteration in range(2):
		point = target + spread + target_velocity * float(result.seconds)
		result = low(origin, point, speed)
		result.solves = iteration + 2
		if not result.valid:
			return result
	return result

static func low(origin: Vector3, target: Vector3, speed: float) -> Dictionary:
	return _solve(origin, target, speed, false)

# Weapon range and orientation eligibility remain the firing system's job.
static func high(origin: Vector3, target: Vector3, speed: float, spread: Vector3 = Vector3.ZERO) -> Dictionary:
	return _solve(origin, target + spread, speed, true)

static func _solve(origin: Vector3, target: Vector3, speed: float, high_branch: bool) -> Dictionary:
	if not origin.is_finite() or not target.is_finite() or not is_finite(speed) or speed <= 0.0:
		return _failure("invalid_initial_conditions", 1)
	var offset := target - origin
	var g := -GRAVITY.y
	var speed_squared := speed * speed
	var q := speed_squared - g * offset.y
	var discriminant := speed_squared * speed_squared - g * (g * (offset.x * offset.x + offset.z * offset.z) + 2.0 * offset.y * speed_squared)
	if not is_finite(discriminant) or discriminant < 0.0:
		return _failure("unreachable", 1)
	var root := sqrt(discriminant)
	# Rationalized low root avoids subtracting nearly equal large values for
	# short-range, high-speed ammunition. No angle trigonometry is required.
	var denominator := q + root
	var time_squared := 2.0 * denominator / (g * g) if high_branch else (2.0 * offset.length_squared() / denominator if denominator > 0.0 else -1.0)
	if not is_finite(time_squared) or time_squared <= 0.0:
		return _failure("no_positive_flight_time", 1)
	var seconds := sqrt(time_squared)
	var velocity := offset / seconds - GRAVITY * (0.5 * seconds)
	if not velocity.is_finite():
		return _failure("invalid_initial_conditions", 1)
	return {"valid":true, "reason":"eligible", "velocity":velocity, "seconds":seconds, "point":target, "solves":1}

# Shared motion primitive for full steps and first/impact partial segments.
# No radius, lifetime, target tracking, damage, or capability state is added.
static func segment(position: Vector3, velocity: Vector3, seconds: float) -> Dictionary:
	if not position.is_finite() or not velocity.is_finite() or not is_finite(seconds) or seconds < 0.0 or seconds > STEP_SECONDS:
		return {"valid":false, "reason":"invalid_segment"}
	var full_step := seconds == STEP_SECONDS
	var velocity_increment := STEP_VELOCITY if full_step else GRAVITY * seconds
	var displacement := STEP_DISPLACEMENT if full_step else GRAVITY * (0.5 * seconds * seconds)
	return {"valid":true, "position":position + velocity * seconds + displacement, "velocity":velocity + velocity_increment, "distance":(velocity + 0.5 * velocity_increment).length() * seconds}

static func _failure(reason: String, solves: int) -> Dictionary:
	return {"valid":false, "reason":reason, "solves":solves}
