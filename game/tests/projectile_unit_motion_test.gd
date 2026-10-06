extends SceneTree

var checks := 0
var failures := 0
var data := ConfirmedGameData.new()

func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL unit motion: "+label)
func body(center: Vector3,basis: Basis = Basis.IDENTITY) -> Dictionary:
	return {"center":center,"extents":Vector3.ONE*0.5,"basis":basis,"team_id":2,"unit_type":UnitDefinition.UnitType.ARMORED_VEHICLE}
func frame(before: Dictionary,after: Dictionary,at: float = 0.0) -> ProjectileUnitMotion:
	var value := ProjectileUnitMotion.new()
	check(value.configure(at,before,after),"valid translated unit frame")
	return value
func emission(at: float = 0.0) -> Dictionary:
	var ammo := data.ammunition("A_556")
	return {"event_id":"test_only:motion:1","emission_order":1,"time_seconds":at,"position":Vector3(0,2,0),"velocity":Vector3(900,0,0),"unit_id":1,"owner_player_id":42,"weapon_instance_id":"test_only:motion/rifle","ammo":ammo}
func run() -> void:
	var h := GravityBallistics.STEP_SECONDS
	var motion := frame({2:body(Vector3(15,2,10))},{2:body(Vector3(15,2,-10))})
	var sim := DB29ProjectileSimulation.new()
	var result := sim.step([emission()],motion)
	check(result.size() == 2 and result[1].hit_unit_id == 2,"crossing target hit despite both endpoint snapshots missing path")
	if result.size() == 2:
		check(absf(result[1].time_seconds-14.5/900.0) < 0.000001,"relative translation earliest contact time")
		check(result[1].normal.x < -0.99,"relative contact world normal")
		check(absf(result[1].velocity.y+10.0*result[1].time_seconds) < 0.00001,"impact gravity velocity at relative contact")
	check(motion.profile.precise_tests == 1,"shared motion broad phase deduplicates candidate")
	sim.collision.close()
	motion = frame({2:body(Vector3(7.5,2,15))},{2:body(Vector3(7.5,2,-5))})
	sim = DB29ProjectileSimulation.new()
	result = sim.step([emission(h*0.5)],motion)
	check(result.size() == 2 and result[1].hit_unit_id == 2,"late emission checks matching residual unit movement")
	sim.collision.close()
	motion = frame({2:body(Vector3(15,2,0))},{2:body(Vector3(15,2,20))})
	sim = DB29ProjectileSimulation.new()
	result = sim.step([emission()],motion)
	check(result.size() == 1 and sim.active_slots.size() == 1,"escaping target not hit using stale step-start position")
	sim.collision.close()
	motion = frame({2:body(Vector3(5,2,10))},{2:body(Vector3(5,2,-10))})
	sim = DB29ProjectileSimulation.new()
	result = sim.step([emission(h*0.5)],motion)
	check(result.size() == 1,"late emission does not compare against whole-step crossing")
	sim.collision.close()
	motion = frame({2:body(Vector3(15,2,10))},{2:body(Vector3(15,2,-10))})
	sim = DB29ProjectileSimulation.new()
	sim.collision.box("wall","obstacle",Vector3(0.01,3,3),Transform3D(Basis.IDENTITY,Vector3(10,2,0)))
	result = sim.step([emission()],motion)
	check(result.size() == 2 and result[1].object_id == "wall","earlier static wall truncates unit query")
	check(motion.profile.precise_tests == 0,"occluded unit excluded before precise relative test")
	sim.collision.close()
	motion = frame({2:body(Vector3(5,2,0))},{2:body(Vector3(5,2,0))})
	sim = DB29ProjectileSimulation.new()
	sim.collision.box("wall","obstacle",Vector3(0.01,3,3),Transform3D(Basis.IDENTITY,Vector3(10,2,0)))
	result = sim.step([emission()],motion)
	check(result.size() == 2 and result[1].hit_unit_id == 2,"closer unit beats later static wall")
	sim.collision.close()
	var friendly := body(Vector3(5,2,0))
	friendly.team_id = 1
	motion = frame({2:friendly},{2:friendly})
	sim = DB29ProjectileSimulation.new()
	result = sim.step([emission()],motion)
	check(result.size() == 2 and result[1].hit_unit_id == 2,"friendship does not provide post-emission collision immunity")
	sim.collision.close()
	motion = frame({2:body(Vector3(5,2,0))},{2:body(Vector3(5,2,0))})
	sim = DB29ProjectileSimulation.new()
	sim.collision.box("wall","obstacle",Vector3(0.5,3,3),Transform3D(Basis.IDENTITY,Vector3(5,2,0)))
	result = sim.step([emission()],motion)
	check(result.size() == 2 and result[1].object_id == "wall","indistinguishable collision times retain static priority")
	sim.collision.close()
	motion = frame({3:body(Vector3(5,2,0)),2:body(Vector3(5,2,0))},{2:body(Vector3(5,2,0)),3:body(Vector3(5,2,0))})
	sim = DB29ProjectileSimulation.new()
	result = sim.step([emission()],motion)
	check(result.size() == 2 and result[1].hit_unit_id == 2,"same-time units use stable object identifier")
	sim.collision.close()
	sim = DB29ProjectileSimulation.new()
	for id: String in ["z_wall","a_wall"]:
		sim.collision.box(id,"obstacle",Vector3(0.5,3,3),Transform3D(Basis.IDENTITY,Vector3(5,2,0)))
	result = sim.step([emission()])
	check(result.size() == 2 and result[1].object_id == "a_wall","same-time static contacts stable despite insertion order")
	sim.collision.close()
	motion = frame({1:body(Vector3(0,2,0))},{1:body(Vector3(10,2,0))})
	sim = DB29ProjectileSimulation.new()
	check(sim.step([emission()],motion).size() == 1,"source excluded in moving unit query")
	sim.collision.close()
	var invalid := ProjectileUnitMotion.new()
	check(invalid.configure(0,{2:body(Vector3.ZERO)},{2:body(Vector3.ZERO,Basis(Vector3.UP,0.1))}) and invalid.records[2].changing,"C-authorized rotating shape supported")
	var changed := body(Vector3.ZERO)
	changed.extents = Vector3.ONE
	check(invalid.configure(0,{2:body(Vector3.ZERO)},{2:changed}) and invalid.records[2].changing,"C-authorized shape interpolation supported")
	changed.extents.x = -1
	check(not invalid.configure(0,{2:body(Vector3.ZERO)},{2:changed}) and invalid.failure_reason == "invalid_unit_motion","invalid shape remains refused")
	check(not invalid.configure(0,{2:body(Vector3.ZERO)},{}) and invalid.failure_reason == "unit_motion_topology_changed","death/spawn timing not guessed")
	check(not invalid.ready and invalid.records.is_empty() and invalid.cells.is_empty(),"failed frame clears partial spatial index")
	sim = DB29ProjectileSimulation.new()
	check(sim.step([emission()],invalid).is_empty() and sim.profile.spawned == 0,"bad frame refused before spawn")
	sim.collision.close()
	motion = frame({2:body(Vector3(5,2,0))},{2:body(Vector3(5,2,0))},h)
	sim = DB29ProjectileSimulation.new()
	check(sim.step([emission()],motion).is_empty() and sim.time_seconds == 0.0,"wrong frame time rejected before timeline advances")
	sim.collision.close()
	motion = frame({2:body(Vector3(5,2,0),Basis(Vector3.UP,0.3))},{2:body(Vector3(5,2,0),Basis(Vector3.UP,0.3))})
	check(not motion.sweep(Vector3(0,2,0),Vector3(30,2,0),0,h,1).is_empty(),"constant oriented box translation supported")
	var many_before := {2:body(Vector3(5,2,0))}
	for id in range(100,1100): many_before[id] = body(Vector3(id*20,2,1000))
	motion = frame(many_before,many_before)
	check(not motion.sweep(Vector3(0,2,0),Vector3(30,2,0),0,h,1).is_empty() and motion.profile.precise_tests == 1,"spatial filtering avoids thousand distant precise tests")
	# Actual shared infantry capture uses one squad body, not one per soldier.
	var unit := UnitState.new(20,42,Vector3.ZERO)
	unit.configure(1,Prototype05DCatalog.new().squad(false))
	var captured := ProjectileUnitMotion.capture({20:unit})
	check(captured.size() == 1 and captured[20].basis == Basis.IDENTITY,"generated test squad retains shared body")
	check(unit.definition.configuration_source.begins_with("test_only:"),"generated unit remains test-only")
	unit.members[0].health = 0.0 # Test setup only, no new damage system.
	check(ProjectileUnitMotion.capture({20:unit}).size() == 1,"surviving squad still one shared hitbox")
	var unconfigured := ProjectileUnitMotion.new()
	check(unconfigured.sweep(Vector3.ZERO,Vector3.ONE,0,h,1).has("failure"),"unconfigured frame does not silently mean zero units")
	var timeline := DB29CombatTimeline.new()
	var aiming := AimingSimulation.new()
	check(timeline.step(aiming,invalid).emissions.is_empty() and timeline.fire.time_seconds == 0.0,"coordinator validates frame before firing/debit")
	timeline.projectiles.collision.close()
	print("Projectile unit motion: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
