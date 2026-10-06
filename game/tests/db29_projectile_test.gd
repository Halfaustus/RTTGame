extends SceneTree

var checks := 0
var failures := 0
var data := ConfirmedGameData.new()

func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL DB29 projectile: "+label)

func emission(id: String,order: int,time: float,position: Vector3 = Vector3(0,2,0)) -> Dictionary:
	var ammo := data.ammunition("A_556")
	return {"event_id":id,"emission_order":order,"time_seconds":time,"position":position,"velocity":Vector3(ammo.initial_speed_mps,0,0),"unit_id":9001,"owner_player_id":42,"weapon_instance_id":"test_only:generated/rifle","ammo":ammo}

func wall(sim: DB29ProjectileSimulation,id: String,x: float,category: String = "obstacle") -> void:
	sim.collision.box(id,category,Vector3(0.01,2,2),Transform3D(Basis.IDENTITY,Vector3(x,2,0)))

func run() -> void:
	var sim := DB29ProjectileSimulation.new()
	var h := GravityBallistics.STEP_SECONDS
	var first := emission("a",1,0.0)
	var second := emission("b",2,h*0.5)
	var events := sim.step([second,first])
	check(events.size() == 2 and events[0].source_event_id == "a","unsorted batch uses emission times")
	check(sim.active_slots.size() == 2,"multiple emissions in one step")
	var a: Dictionary = sim.slots[sim.active_ids.a]
	var b: Dictionary = sim.slots[sim.active_ids.b]
	check(absf(a.position.x-30.0) < 0.0001,"full first step")
	check(absf(b.position.x-15.0) < 0.0001,"late projectile only residual half step")
	check(absf(a.velocity.y+10.0*h) < 0.00001,"gravity updated velocity")
	check(absf(b.position.y-(2.0-5.0*h*h*0.25)) < 0.00001,"partial gravity displacement")
	check(is_equal_approx(sim.time_seconds,h),"shared fixed-step clock")
	var count: int = sim.profile.spawned
	check(sim.step([first]).is_empty() and sim.failure_reason == "invalid_emission_batch","duplicate rejected explicitly")
	check(sim.profile.spawned == count and sim.time_seconds == h,"invalid batch no state mutation")
	var future := emission("future",3,h*3)
	check(sim.step([future]).is_empty() and sim.time_seconds == h,"future timestamp refused without moving clock")
	var unknown := emission("unknown",3,h)
	unknown.ammo = data.ammunition("A_CG_HE")
	check(sim.step([unknown]).is_empty(),"unconfigured initial speed never guessed")
	var wrong := emission("wrong",3,h)
	wrong.velocity = Vector3(100,0,0)
	check(sim.step([wrong]).is_empty(),"old prototype speed cannot override DATA")
	var edge := emission("edge",3,2*h)
	events = sim.step([edge])
	check(events.size() == 1 and sim.slots[sim.active_ids.edge].position == edge.position,"step-end emission has zero elapsed")
	check(sim.slots[sim.active_ids.edge].velocity == edge.velocity,"step-end emission no extra gravity")
	# No source pointers are retained: remove a generated test unit after spawn.
	var unit := UnitState.new(9001,42,Vector3.ZERO)
	unit.configure(1,Prototype05DCatalog.new().squad(false))
	check(unit.definition.configuration_source.begins_with("test_only:"),"source unit remains generated TEST ONLY")
	unit = null
	sim.step()
	check(sim.active_slots.size() == 3,"source removal cannot cancel flight")
	check(sim.collision.profile.casts == 0 and sim.collision.profile.ray_queries > 0,"point rays, no sphere casts")
	sim.collision.close()
	sim = DB29ProjectileSimulation.new()
	wall(sim,"far",20)
	wall(sim,"near",9)
	events = sim.step([emission("hit",1,0)])
	check(events.size() == 2 and events[1].reason == "impact","spawn and impact in same step")
	if events.size() == 2:
		var hit: Dictionary = events[1]
		check(hit.object_id == "near","earliest collision despite registration order")
		check(absf(hit.point.x-8.99) < 0.0001,"no prototype radius inflation")
		check(absf(hit.time_seconds-8.99/900.0) < 0.000001,"actual substep impact time")
		check(absf(hit.velocity.y+10.0*hit.time_seconds) < 0.00001,"velocity at impact time")
		check(absf(hit.position.y-(2.0-5.0*hit.time_seconds*hit.time_seconds)) < 0.00001,"analytic position at impact time")
		var expected_distance: float = (Vector3(900,0,0)+0.5*GravityBallistics.GRAVITY*hit.time_seconds).length()*hit.time_seconds
		check(absf(hit.distance_m-expected_distance) < 0.00001,"midpoint path accumulated to impact")
		check(hit.owner_player_id == 42 and hit.unit_id == 9001,"fixed source attribution")
	check(sim.active_slots.is_empty() and sim.free_slots.size() == 1,"terminal frees central slot")
	check(sim.slots[0].is_empty(),"slot clears source ammo and ignore state")
	check(sim.step().is_empty() and sim.profile.impacts == 1,"single terminal event")
	events = sim.step([emission("reused",2,sim.time_seconds)])
	check(sim.slots.size() == 1 and sim.profile.reuses == 1,"reusable storage without capacity shot loss")
	check(events[0].slot_generation == 2,"generation distinguishes reused slot")
	sim.collision.close()
	sim = DB29ProjectileSimulation.new()
	wall(sim,"house:7",3,"house")
	wall(sim,"wreck",4,"wreck")
	wall(sim,"smoke",5,"smoke")
	wall(sim,"trees",6,"trees")
	wall(sim,"valid",9)
	var ignored := emission("ignore",1,0)
	ignored.ignore_house_id = 7
	events = sim.step([ignored])
	check(events.size() == 2 and events[1].object_id == "valid","house exclusions and nonblocking objects")
	# Reuse must not inherit the previous shot's house exclusions.
	events = sim.step([emission("fresh",2,sim.time_seconds)])
	check(events.size() == 2 and events[1].object_id == "house:7","reused slot does not inherit ignored house")
	sim.collision.close()
	sim = DB29ProjectileSimulation.new()
	wall(sim,"wall",9)
	var slower_arrival := emission("z",1,0,Vector3(-9,2,0))
	var faster_arrival := emission("a",2,h*0.001)
	events = sim.step([slower_arrival,faster_arrival])
	var impacts: Array[Dictionary] = []
	for event: Dictionary in events:
		if event.reason == "impact": impacts.append(event)
	check(impacts.size() == 2 and impacts[0].source_event_id == "a","impact events ordered by time, not storage")
	sim.collision.close()
	sim = DB29ProjectileSimulation.new()
	wall(sim,"wall",9)
	events = sim.step([emission("a",1,0),emission("b",2,0)])
	impacts.clear()
	for event: Dictionary in events:
		if event.reason == "impact": impacts.append(event)
	check(impacts.size() == 2 and impacts[0].source_event_id == "a","equal-time events stable projectile IDs")
	sim.collision.close()
	sim = DB29ProjectileSimulation.new()
	sim.collision.close()
	sim.step([emission("failure",1,0)])
	check(sim.halted and not sim.failure_reason.is_empty() and sim.active_slots.size() == 1,"query failure halts without silently deleting shot")
	check(sim.step().is_empty() and sim.time_seconds == 0.0,"failed timeline cannot continue partially")
	sim = DB29ProjectileSimulation.new()
	sim.collision.close()
	sim.step([emission("failure-first",1,0),emission("failure-later",2,0)])
	check(sim.profile.updates == 1 and sim.active_slots.size() == 2,"first query failure stops the entire batch and preserves both shots")
	var later: Dictionary = sim.slots[sim.active_ids["failure-later"]]
	check(later.time_seconds == 0.0 and later.distance_m == 0.0,"later shot remains unadvanced after query failure")
	sim = DB29ProjectileSimulation.new()
	var high := GravityBallistics.high(Vector3(0,2,0),Vector3(100,2,0),225.0)
	var mortar := emission("mortar",1,0)
	mortar.ammo = data.ammunition("A_M252_HE")
	mortar.velocity = high.velocity
	sim.step([mortar])
	for index in range(299): sim.step()
	var flying: Dictionary = sim.slots[sim.active_ids.mortar]
	check(sim.active_slots.size() == 1,"no old eight-second lifetime expiry")
	check(flying.position.distance_to(Vector3(0,2,0)+high.velocity*10.0+0.5*GravityBallistics.GRAVITY*100.0) < 0.02,"high arc ten seconds uses same gravity consumer")
	check(flying.velocity.distance_to(high.velocity+GravityBallistics.GRAVITY*10.0) < 0.005,"high and low share motion update")
	sim.collision.close()
	print("DB29 projectiles: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
