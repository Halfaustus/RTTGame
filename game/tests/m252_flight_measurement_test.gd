extends "res://tests/db29_projectile_test.gd"

func run() -> void:
	var results: Array[Dictionary] = []
	var measurement_directory := "res://../tmp/cleanup-07/m252-" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(measurement_directory))
	for requested_range in [100.0,150.0,200.0,250.0,300.0,350.0,500.0,900.0,1200.0,1500.0,1800.0]:
		var model = load("res://scripts/networking/network_manager.gd").new()
		root.add_child(model)
		check(model.configure_active_test_map(),"activity navigation initialized")
		var expanded: bool = requested_range>400
		if expanded:
			# Measurement-only boundary extension. Persist the isolated configuration
			# outside production so settlement has its real path and content hash.
			var config: MovementConfig = model._movement._config.duplicate()
			config.resource_name="TEST ONLY M252 maximum range measurement"
			config.maximum_xz.y=1700
			var config_path := measurement_directory.path_join("range-%d.tres" % requested_range)
			check(ResourceSaver.save(config,config_path) == OK,"measurement configuration saved outside production")
			config = load(config_path)
			check(config != null and not config.resource_path.is_empty(),"measurement configuration has settlement identity")
			model._movement=MovementSimulation.new(config)
			check(model._movement.initialize_navigation(),"measurement-only range fits navigation")
		check(model._ensure_deployment_ready(),"actual deployment configured")
		var unit := UnitState.new(9910,42,Vector3(100,0.5,-180) if expanded else Vector3(100,0.5,180))
		unit.configure(1,preload("res://data/units/db33_active_test_mortar.tres"))
		unit.owner_player_id=10
		model._authoritative_units[unit.unit_id]=unit
		model._movement.add_unit(unit)
		model._combat.add_unit(unit)
		model._aiming.units=model._authoritative_units
		model._peer_players[42]=10
		var weapon: RuntimeWeaponInstance = unit.runtime_weapons[0]
		var position := weapon.world_position()
		# 1mm inside configured max prevents floating-point edge rejection.
		var distance: float = requested_range-0.001 if expanded else requested_range
		var point := Vector3(position.x,0,position.z+(1 if expanded else -1)*sqrt(distance*distance-position.y*position.y))
		var spawns: Array[Dictionary] = []
		var terminals: Array[Dictionary] = []
		model.projectile_spawn_received.connect(func(event): spawns.append(event))
		model.projectile_terminal_received.connect(func(event): terminals.append(event))
		var accepted: Dictionary = model._execute_command({"type":"artillery","unit_ids":[unit.unit_id],"target":point,"count":1,"peer_id":42,"player_id":10})
		check(accepted.unit_ids==[unit.unit_id],"T accepted at %sm" % requested_range)
		for tick in range(650):
			model._run_server_tick(PackedInt32Array())
			if not terminals.is_empty(): break
		check(spawns.size()==1 and terminals.size()==1 and not model._combat_timeline.halted,"single real flight terminates at %sm" % requested_range)
		if spawns.size()==1 and terminals.size()==1:
			var launch: Dictionary=spawns[0]
			var end: Dictionary=terminals[0]
			var velocity: Vector3=launch.velocity
			var horizontal := Vector2(velocity.x,velocity.z).length()
			var flight_time := float(end.time_seconds)-float(launch.time_seconds)
			var analytic_ground_time: float = (velocity.y+sqrt(velocity.y*velocity.y+20*launch.position.y))/10
			# Use actual ground collision, not the unscattered command position.
			var nominal_high := GravityBallistics.high(launch.position,end.point,velocity.length())
			var nominal_low := GravityBallistics.low(launch.position,end.point,velocity.length())
			check(is_nan(weapon.definition.ammo_definitions[0].initial_speed_mps),"indirect DATA speed not applicable")
			check(flight_time <= 20 and flight_time > 0,"actual full-range impact within 20 seconds")
			check(absf(float(nominal_high.seconds)-flight_time)<0.001 and float(nominal_high.seconds)>float(nominal_low.seconds),"actual chosen velocity remains longer-time branch")
			check(end.reason=="impact" and end.object_id=="ground" and absf(end.point.y)<0.00001 and absf(end.position.y-end.point.y)<=10*pow(GravityBallistics.STEP_SECONDS,2)/8+0.00002,"real ground terminal, not forced lifetime")
			check(absf(flight_time-analytic_ground_time)<0.001,"point simulation matches actual sampled launch analytic time")
			results.append({"range_m":requested_range,"weapon_distance_m":position.distance_to(point),"speed_mps":velocity.length(),"angle_degrees":rad_to_deg(atan2(velocity.y,horizontal)),"apex_m":float(launch.position.y)+velocity.y*velocity.y/20,"flight_seconds":flight_time,"nominal_high_seconds":nominal_high.seconds,"nominal_low_seconds":nominal_low.seconds,"command_to_impact_seconds":float(end.time_seconds),"over_20s":flight_time>20,"expanded_measurement_bounds":expanded,"launch_position":[launch.position.x,launch.position.y,launch.position.z],"terminal_position":[end.position.x,end.position.y,end.position.z],"terminal_reason":end.reason})
			print("M252 %.0fm | %.3fm/s | high %.4fdeg | apex %.3fm | flight %.5fs | low %.5fs | expanded=%s" % [requested_range,velocity.length(),rad_to_deg(atan2(velocity.y,horizontal)),float(launch.position.y)+velocity.y*velocity.y/20,flight_time,nominal_low.seconds,expanded])
		if model._projectiles!=null: model._projectiles.collision.close()
		model.free()
	var output:=FileAccess.open(measurement_directory.path_join("measurements.json"),FileAccess.WRITE)
	output.store_string(JSON.stringify({"weapon":"W_M252","ammo":"A_M252_HE","gravity":10,"random_seed":50506,"results":results},"  "))
	output.close()
	print("M252 actual chain measurements: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
