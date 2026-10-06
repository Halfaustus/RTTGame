extends SceneTree

var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL gravity: " + label)

func endpoint(origin: Vector3, solution: Dictionary) -> Vector3:
	var time: float = solution.seconds
	return origin + solution.velocity * time + 0.5 * GravityBallistics.GRAVITY * time * time

func _initialize() -> void:
	var data := ConfirmedGameData.new()
	check(is_equal_approx(data.ammunition("A_556").initial_speed_mps,900.0),"rifle speed from DATA km/h")
	check(is_nan(data.ammunition("A_M252_HE").initial_speed_mps) and data.ammunition("A_M252_HE").distance_selected_launch,"indirect speed selected at emission, not DATA")
	check(is_nan(data.ammunition("A_CG_HE").initial_speed_mps),"missing HE speed remains unconfigured")
	for row: Dictionary in data.records.Ammo:
		var expected := data.number(row,"Projectile_Speed_kmh") / 3.6
		var actual := data.ammunition(row.Ammo_ID).initial_speed_mps
		check(is_nan(actual) if is_nan(expected) else is_equal_approx(actual,expected),"per-ammunition speed " + str(row.Ammo_ID))
	# Automatically constructed, test-only units. No formal INF configuration,
	# attack eligibility, spread radius or pending ammunition is fabricated.
	var origin_unit := UnitState.new(91001,41,Vector3(0,2,0))
	origin_unit.configure(1,Prototype05DCatalog.new().squad(false))
	var target_unit := UnitState.new(91002,42,Vector3(100,7,-30))
	target_unit.configure(2,Prototype05DCatalog.new().squad(true))
	check(origin_unit.definition.configuration_source.begins_with("test_only:"),"generated source is test-only")
	check(target_unit.definition.configuration_source.begins_with("test_only:"),"generated target is test-only")
	var origin := origin_unit.position
	var target := target_unit.position
	var speed := data.ammunition("A_556").initial_speed_mps
	var low := GravityBallistics.low(origin,target,speed)
	check(low.valid,"unequal-height low solution")
	check(endpoint(origin,low).distance_to(target) < 0.001,"low endpoint")
	check(absf(low.velocity.length()-speed) < 0.01,"low preserves confirmed initial speed")
	var high := GravityBallistics.high(origin,target,225.0)
	check(high.valid and high.seconds > low.seconds,"high positive flight time")
	check(endpoint(origin,high).distance_to(target) < 0.01,"high endpoint")
	check(absf(high.velocity.length()-225.0) < 0.001,"high preserves speed")
	var same_speed_low := GravityBallistics.low(origin,target,225.0)
	check(high.seconds > same_speed_low.seconds,"high selects longer branch")
	var boundary := Vector3(1000,0,0)
	var coalesced_low := GravityBallistics.low(Vector3.ZERO,boundary,100.0)
	var coalesced_high := GravityBallistics.high(Vector3.ZERO,boundary,100.0)
	check(coalesced_low.valid and coalesced_high.valid and is_equal_approx(coalesced_low.seconds,coalesced_high.seconds),"coalesced branches unique")
	check(not GravityBallistics.low(Vector3.ZERO,Vector3(1001,0,0),100.0).valid,"unreachable low refuses")
	check(not GravityBallistics.high(Vector3.ZERO,Vector3(1001,0,0),100.0).valid,"unreachable high refuses")
	for height in [-5.0,5.0]:
		var vertical := Vector3(0,height,0)
		var solution := GravityBallistics.high(Vector3.ZERO,vertical,100.0)
		check(solution.valid and endpoint(Vector3.ZERO,solution).distance_to(vertical) < 0.01,"vertical high common formula")
	check(GravityBallistics.high(Vector3.ZERO,Vector3.ZERO,100.0).valid,"zero horizontal high has positive time")
	check(not GravityBallistics.low(Vector3.ZERO,Vector3.ZERO,100.0).valid,"zero-time low refuses")
	check(not GravityBallistics.low(origin,target,NAN).valid,"missing speed refuses")
	check(not GravityBallistics.direct(origin,target,Vector3(INF,0,0),speed).valid,"invalid target velocity refuses")
	var spread := Vector3(0.15,0.05,-0.03) # Isolated one-shot test offset, not formal spread.
	var stationary := GravityBallistics.direct(origin,target,Vector3.ZERO,speed,spread)
	check(stationary.valid and stationary.solves == 1,"stationary one solve")
	check(stationary.point == target + spread,"stationary uses supplied spread once")
	var movement := Vector3(0,0,20)
	var t0 := GravityBallistics.low(origin,target+spread,speed)
	var t1 := GravityBallistics.low(origin,target+spread+movement*t0.seconds,speed)
	var moving := GravityBallistics.direct(origin,target,movement,speed,spread)
	check(moving.valid and moving.solves == 3,"moving exactly three solves")
	check(moving.point.distance_to(target+spread+movement*t1.seconds) < 0.0001,"two predictions retain same spread")
	check(endpoint(origin,moving).distance_to(moving.point) < 0.001,"moving solution reaches final predicted point")
	var failed_prediction := GravityBallistics.direct(Vector3.ZERO,Vector3(990,0,0),Vector3(1000,0,0),100.0)
	check(not failed_prediction.valid and failed_prediction.solves == 2,"failed prediction refuses without fallback")
	var position := origin
	var velocity: Vector3 = low.velocity
	var travelled := 0.0
	for index in range(30):
		var segment := GravityBallistics.segment(position,velocity,GravityBallistics.STEP_SECONDS)
		position = segment.position
		velocity = segment.velocity
		travelled += segment.distance
	check(position.distance_to(origin+low.velocity+0.5*GravityBallistics.GRAVITY) < 0.01,"thirty steps match one-second analytic motion")
	check(velocity.distance_to(low.velocity+GravityBallistics.GRAVITY) < 0.001,"shared gravity velocity increment")
	check(travelled > position.distance_to(origin),"travel accumulates path rather than source displacement")
	var partial_time := GravityBallistics.STEP_SECONDS * 0.3
	var partial := GravityBallistics.segment(origin,low.velocity,partial_time)
	check(partial.position.distance_to(origin+low.velocity*partial_time+0.5*GravityBallistics.GRAVITY*partial_time*partial_time) < 0.0001,"new emission residual segment")
	check(is_equal_approx(partial.distance,(low.velocity+0.5*GravityBallistics.GRAVITY*partial_time).length()*partial_time),"partial impact midpoint distance")
	var zero := GravityBallistics.segment(origin,low.velocity,0.0)
	check(zero.valid and zero.position == origin and zero.distance == 0.0,"zero segment unchanged")
	check(not GravityBallistics.segment(origin,low.velocity,-1.0).valid,"negative time rejected")
	check(not GravityBallistics.segment(origin,low.velocity,0.1).valid,"large segment rejected rather than silently merging")
	# Source removal does not affect a solution already expressed in values.
	origin_unit = null
	target_unit = null
	check(GravityBallistics.segment(origin,low.velocity,GravityBallistics.STEP_SECONDS).valid,"flight primitive independent of source lifetime")
	print("Gravity ballistics: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
