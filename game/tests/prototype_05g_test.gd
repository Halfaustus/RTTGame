extends SceneTree

var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("0.5G: " + label)

func _initialize() -> void:
	var data := ConfirmedGameData.new()
	var ammo := data.ammunition("A_M252_HE")
	var snapshot: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ConfirmedGameData.PATH))
	check(snapshot.source_sha256 == FileAccess.get_sha256("res://../docs/RTT_GAME_DATA.xlsx").to_upper(),"snapshot identifies amended workbook")
	for row: Dictionary in data.records.Ammo:
		if data.record("Weapons",row.Weapon_ID).get("Class","") == "迫击炮":
			check(row.Projectile_Speed_kmh == "不适用","all current indirect rows omit fixed speed")
	check(data.record("Ammo","A_M252_HE").Projectile_Speed_kmh == "不适用" and is_nan(ammo.initial_speed_mps) and ammo.distance_selected_launch,"indirect DATA no fixed speed")
	check(not data.ammunition("A_556").distance_selected_launch and data.ammunition("A_556").initial_speed_mps == 900,"direct speed unchanged")
	check(is_nan(data.ammunition("A_CG_HE").initial_speed_mps) and not data.ammunition("A_CG_HE").distance_selected_launch,"missing direct speed not granted indirect eligibility")
	var previous_speed := 0.0
	for distance in range(100,1801):
		var point := Vector3(float(distance),0,0)
		var result := GravityBallistics.indirect(Vector3.ZERO,point)
		check(result.valid and result.seconds <= 20,"whole M252 range within time bound")
		if not result.valid: continue
		var velocity: Vector3 = result.velocity
		var seconds: float = result.seconds
		check((velocity*seconds+0.5*GravityBallistics.GRAVITY*seconds*seconds).distance_to(point)<0.001,"physical endpoint")
		check(velocity.y > absf(velocity.x) and velocity.length()>previous_speed,"high arc and distance speed scaling")
		previous_speed = velocity.length()
	# Elevation and spread enter the SAME actual launch solve, not a post-hoc teleport.
	for height in [-100.0,-5.0,5.0,100.0]:
		var origin := Vector3(0,2,0)
		var target := origin+Vector3(1700,height,0)
		var spread := Vector3(0.1,0.05,-0.15)
		var result := GravityBallistics.indirect(origin,target,spread)
		var high := GravityBallistics.high(origin,target+spread,result.velocity.length())
		var low := GravityBallistics.low(origin,target+spread,result.velocity.length())
		check(result.valid and result.seconds<20 and absf(result.seconds-high.seconds)<0.001 and high.seconds>low.seconds,"height/spread keeps longer branch")
		check((origin+result.velocity*result.seconds+0.5*GravityBallistics.GRAVITY*result.seconds*result.seconds).distance_to(target+spread)<0.002,"height/spread physical endpoint")
	check(not GravityBallistics.indirect(Vector3.ZERO,Vector3(3000,0,0)).valid,"infeasible future range rejects instead of low-arc/time compression")
	check(not GravityBallistics.indirect(Vector3.ZERO,Vector3.ZERO).valid,"zero path fails explicitly")
	check(not GravityBallistics.indirect(Vector3.ZERO,Vector3(INF,0,0)).valid,"invalid geometry fails")
	var preview := ArtilleryPreview.new()
	var source := {"definition_id":"W_M252","weapon_position":Vector3.ZERO,"muzzle_position":Vector3(0,0.5,0),"inventory":{"A_M252_HE":24}}
	var described := preview.describe(source,Vector3(1800,0,0))
	var nominal := GravityBallistics.indirect(source.muzzle_position,Vector3(1800,0,0))
	check(described.valid and described.velocity.distance_to(nominal.velocity)<0.0001 and described.seconds == nominal.seconds,"preview reuses authority launch formula")
	check(not preview.describe(source,Vector3(99,0,0)).valid and not preview.describe(source,Vector3(1801,0,0)).valid,"formal minimum/maximum preserved")
	preview.free()
	var pool := DB29ProjectileSimulation.new()
	var direct := data.ammunition("A_CG_HE")
	var invalid: Dictionary = {"event_id":"test:missing_direct","emission_order":1,"time_seconds":0.0,"position":Vector3.ZERO,"velocity":Vector3(100,10,0),"ammo":direct,"unit_id":1,"owner_player_id":1,"weapon_instance_id":"test:direct"}
	check(not pool._valid(invalid,GravityBallistics.STEP_SECONDS),"missing direct speed still rejected at pool")
	invalid.ammo = ammo
	check(pool._valid(invalid,GravityBallistics.STEP_SECONDS),"indirect pool consumes authoritative runtime launch velocity")
	invalid.velocity = Vector3.ZERO
	check(not pool._valid(invalid,GravityBallistics.STEP_SECONDS),"indirect cannot spawn stationary projectile")
	# An isolated authority launch demonstrates the consumer has no 20s TTL.
	# The firing policy rejects this long solution; the physics pool stays generic.
	invalid.velocity = Vector3(0,225,0)
	pool.step([invalid])
	for tick in range(630): pool.step()
	check(pool.active_slots.size() == 1 and not pool.halted,"20s launch policy is not a physics lifetime")
	pool.collision.close()
	print("0.5G: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
