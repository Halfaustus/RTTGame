class_name InfantrySuppressionState
extends RefCounted

# Server-only state. The event coordinator owns ordering with damage/firing.
# No automatic defaults: callers supply confirmed configuration explicitly.
enum PersonnelState { CALM, PANIC, DISABLED, DEAD }
var configured_count := 0
var alive_count := 0
var allowance := 0.0
var recovery_wait := 0.0
var recovery_fraction := 0.0
var q := 0.0
var time_seconds := 0.0
var last_effective_event := -INF
var ready := false

func configure(count: int,per_person: float,wait: float,fraction: float,at: float = 0.0) -> bool:
	if count <= 0 or not finite_nonnegative(at) or not finite_nonnegative(wait) or not finite_nonnegative(fraction) or fraction > 1.0 or not is_finite(per_person) or per_person <= 0: return false
	configured_count = count
	alive_count = count
	allowance = per_person
	recovery_wait = wait
	recovery_fraction = fraction
	q = 0.0
	time_seconds = at
	last_effective_event = -INF
	ready = true
	return true

func advance_to(at: float) -> bool:
	if not ready or not finite_nonnegative(at) or at < time_seconds: return false
	if alive_count > 0 and q > 0 and is_finite(last_effective_event):
		var start := maxf(time_seconds,last_effective_event+recovery_wait)
		var elapsed := maxf(0.0,at-start)
		q = maxf(0.0,q-elapsed*configured_count*allowance*recovery_fraction)
	time_seconds = at
	return true

# Caller must advance to the actual event time before changing membership.
# Membership changes neither add suppression nor refresh the safe timer.
func set_alive_count(count: int) -> bool:
	if not ready or count < 0 or count > configured_count: return false
	alive_count = count
	q = minf(q,2.0*alive_count*allowance)
	return true

# Includes zero-damage/zero-amount effective events. Being aimed at must never
# call this entry point. No damage mutation or implicit event ordering here.
func effective_event(amount: float) -> bool:
	if not ready or alive_count <= 0 or not finite_nonnegative(amount): return false
	q = minf(q+amount,2.0*alive_count*allowance)
	last_effective_event = time_seconds
	return true

func personnel_state() -> int:
	if alive_count == 0: return PersonnelState.DEAD
	if q >= 2.0*alive_count*allowance: return PersonnelState.DISABLED
	if q >= alive_count*allowance: return PersonnelState.PANIC
	return PersonnelState.CALM

func ratio() -> float:
	return q/(2.0*alive_count*allowance) if ready and alive_count > 0 else 0.0

func modifiers(right_limit: bool = false) -> Dictionary:
	var status := personnel_state()
	# Integrate durations over the open interval after an exact threshold.
	# Q itself and point-in-time state retain the confirmed inclusive boundary.
	if right_limit and alive_count > 0 and recovery_fraction > 0 and time_seconds >= last_effective_event+recovery_wait:
		if q == 2.0*alive_count*allowance: status = PersonnelState.PANIC
		elif q == alive_count*allowance: status = PersonnelState.CALM
	var duration := 5.0 if status == PersonnelState.DISABLED else (2.0 if status == PersonnelState.PANIC else 1.0)
	return {"movement":1.0/duration,"vision":1.0/duration,"aim_time_multiplier":duration,
		"personnel_load_multiplier":duration,"spread_multiplier":duration,"mechanical_load_multiplier":1.0}

func next_boundary() -> float:
	if not ready or alive_count == 0 or q <= 0 or recovery_fraction <= 0: return INF
	var start := last_effective_event+recovery_wait
	if start > time_seconds: return start
	var rate := configured_count*allowance*recovery_fraction
	var target := alive_count*allowance if q > alive_count*allowance else 0.0
	return time_seconds+(q-target)/rate

static func finite_nonnegative(value: float) -> bool:
	return is_finite(value) and value >= 0.0
