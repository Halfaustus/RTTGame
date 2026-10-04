extends SceneTree

var checks := 0
var failures := 0
var simulation: ProjectileSimulation
var catalog := Prototype05DCatalog.new()
var order := 0

func _initialize() -> void: run.call_deferred()
func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL 0.5F: "+label)
func reset() -> void:
	if simulation != null: simulation.collision.close()
	simulation = ProjectileSimulation.new()
	order = 0
func event(position: Vector3 = Vector3(0,1,0), velocity: Vector3 = Vector3(100,0,0), radius: float = 0.025, lifetime: float = 2) -> Dictionary:
	order += 1
	return {"event_id":"fixture:"+str(order),"emission_order":order,"emission_sequence":order,"unit_id":1,"owner_player_id":42,"team_id":1,"weapon_instance_id":"1/0/1/primary","slot_id":"primary","time_seconds":0.0,"position":position,"direction":velocity.normalized(),"projectile":{"trajectory":"direct","speed_mps":velocity.length(),"radius_m":radius,"lifetime_seconds":lifetime},"ammo_definition_id":"standard","consumed":3,"target_id":123}
func wall(id: String, x: float, kind: String = "obstacle", blocks: bool = true) -> void:
	simulation.collision.box(id,kind,Vector3(0.01,2,2),Transform3D(Basis.IDENTITY,Vector3(x,1,0)),0,0,blocks)
func run() -> void:
	reset()
	var source := event()
	check(simulation.consume([source]).size() == 1 and simulation.active.size() == 1,"triplet one projectile")
	check(simulation.consume([source]).is_empty() and simulation.profile.spawned == 1,"duplicate does not spawn")
	check(source.consumed == 3,"consumer does not change debit")
	wall("thin",5)
	var ends := simulation.advance(0.1,1)
	check(ends.size() == 1,"ten Hz swept thin wall")
	if ends.size() == 1:
		check(ends[0].object_id == "thin" and ends[0].reason == "impact","wall impact classification")
		check(absf(ends[0].distance_m-4.965) < 0.003,"sphere radius affects distance")
		check(absf(ends[0].point.x-4.99) < 0.003 and ends[0].normal.x < -0.99,"contact point and normal")
		check(absf(ends[0].time_seconds-0.04965) < 0.0001,"sub tick contact time")
		check(ends[0].owner_player_id == 42 and ends[0].source_event_id == source.event_id,"fixed source ownership")
	check(simulation.active.is_empty() and simulation.advance(10,2).is_empty(),"single termination and cleanup")
	reset()
	wall("far",8)
	wall("near",3)
	simulation.consume([event()])
	ends = simulation.advance(0.1,1)
	check(ends.size() == 1 and ends[0].object_id == "near","earliest not registration order")
	reset()
	wall("house:7",2,"house")
	wall("wreck",3,"wreck")
	wall("trees",4,"trees")
	wall("smoke",5,"smoke")
	wall("valid",6)
	source = event()
	source.ignore_house_id = 7
	simulation.consume([source])
	ends = simulation.advance(0.1,1)
	check(ends.size() == 1 and ends[0].object_id == "valid","excluded house and non blocking objects cannot hide later hit")
	reset()
	var owner := UnitState.new(1,42,Vector3(0,1,0))
	owner.owner_player_id = 42
	owner.configure(1,catalog.squad(true))
	var victim := UnitState.new(202,0,Vector3(5,1,0))
	victim.configure(1,catalog.vehicle("a"))
	var states: Dictionary[int,UnitState] = {1:owner,202:victim}
	simulation.collision.sync_units(states)
	var hp := victim.health
	source = event()
	simulation.consume([source])
	ends = simulation.advance(0.1,1)
	check(ends.size() == 1 and ends[0].hit_unit_id == 202,"self excluded, friendly non original type collides")
	check(victim.health == hp,"no vehicle damage")
	check(owner.runtime_weapons.size() == 8,"existing runtime composition retained")
	states.erase(202)
	simulation.collision.sync_units(states)
	check(not simulation.collision.bodies.has("unit:202"),"removed bodies evicted")
	owner.health = 0
	simulation.collision.sync_units(states)
	check(not simulation.collision.bodies.has("unit:1"),"dead squad no corpse blocker")
	reset()
	victim = UnitState.new(5,0,Vector3(5,1,0))
	victim.configure(2,catalog.squad(false))
	simulation.collision.sync_units({5:victim})
	check(simulation.collision.bodies.size() == 1,"one shared squad collision body")
	var member_hp := victim.member_health
	source = event()
	source.ammo_definition_id = "cannon_a_he"
	source.explosion_radius_m = 2
	simulation.consume([source])
	ends = simulation.advance(0.1,1)
	check(ends.size() == 1 and ends[0].hit_unit_id == 5 and not ends[0].has("member_id"),"squad impact no invented member selection")
	check(victim.member_health == member_hp and ends.size() == 1,"HE no area damage or extra events")
	reset()
	source = event(Vector3(0,1,0),Vector3(10,0,0),0.025,0.25)
	simulation.consume([source])
	source.position = Vector3(99,1,0)
	source.target_id = 999
	ends = simulation.advance(1,1)
	check(ends.size() == 1 and ends[0].reason == "expired" and ends[0].position == Vector3(2.5,1,0),"expiry clamps dt, ignores mutable source and target")
	check(ends[0].distance_m == 2.5 and ends[0].time_seconds == 0.25,"real flight length and expiry time")
	check(simulation.active.is_empty() and simulation.last_emission_order == 1,"bounded lifecycle dedup scalar")
	reset()
	simulation.bounds = Rect2(Vector2(-1,-1),Vector2(3,2))
	simulation.consume([event()])
	ends = simulation.advance(0.1,1)
	check(ends.size() == 1 and ends[0].reason == "map_boundary" and is_equal_approx(ends[0].distance_m,2),"existing map boundary independent of range")
	reset()
	wall("point_wall",5)
	simulation.consume([event(Vector3(0,1,0),Vector3(100,0,0),0)])
	ends = simulation.advance(0.1,1)
	check(ends.size() == 1 and simulation.collision.profile.ray_queries == 1,"explicit point fixture ray")
	reset()
	wall("overlap",0)
	simulation.consume([event()])
	ends = simulation.advance(0.1,1)
	check(ends.size() == 1 and ends[0].distance_m == 0,"initial overlap not ignored by cast_motion")
	ballistic_checks()
	additional_checks()
	await production_checks()
	if simulation != null: simulation.collision.close()
	print("0.5F: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func ballistic_checks() -> void:
	var solution := DirectBallistics.lead(Vector3.ZERO,Vector3(0,0,-100),Vector3(10,0,0),100)
	check(solution.valid and solution.point.x > 10 and is_equal_approx(solution.point.length()/100,solution.seconds),"intercept uses present target velocity")
	check(not DirectBallistics.lead(Vector3.ZERO,Vector3(0,0,-100),Vector3(0,0,-200),100).valid,"unreachable intercept explicit")
	var first := RandomNumberGenerator.new()
	first.seed = 50506
	var second := RandomNumberGenerator.new()
	second.seed = 50506
	var offset := DirectBallistics.spread_offset(first,0.15,Vector3.FORWARD)
	check(offset == DirectBallistics.spread_offset(second,0.15,Vector3.FORWARD) and offset.length() <= 0.15,"seeded fixed world disk radius")
	var vehicle := UnitState.new(8,42,Vector3(1,1,1))
	vehicle.configure(1,catalog.vehicle("c"))
	vehicle.yaw = PI/2
	vehicle.mounts[0].world_yaw = 0
	var main := vehicle.runtime_weapons[0]
	check(DirectBallistics.muzzle(main) == vehicle.position+Prototype05FConfig.MAIN_MUZZLE,"main world yaw not relative yaw")
	check(DirectBallistics.muzzle(vehicle.runtime_weapons[3]) != DirectBallistics.muzzle(main),"Hull and turret muzzle distinct")
	check(DirectBallistics.muzzle(main,{"house_center":Vector3(4,2,4)}) == Vector3(4,2,4),"indoor origin uses house center")
	var defense := UnitState.new(10,42,Vector3.ZERO)
	defense.configure(1,catalog.squad(false))
	check(defense.runtime_weapons.size() == 8 and defense.unassigned_inventory.rocket_ap == 5,"unassigned rockets never instantiate")
	var feed := PresentationFeed.new()
	var fixture := ProjectileState.new(event()).spawn_event()
	feed.apply_projectile_spawn(fixture)
	feed.apply_projectile_spawn(fixture)
	check(feed.live_projectiles.size() == 1,"presentation spawn dedup")
	check(feed.projectile_position(fixture.projectile_id,0.05) == Vector3(5,1,0),"linear presentation interpolation")
	feed.unit_death_received.emit(1)
	check(feed.live_projectiles.size() == 1,"source death does not cancel presentation projectile")
	feed.apply_projectile_terminal({"projectile_id":fixture.projectile_id})
	check(feed.live_projectiles.is_empty(),"authoritative termination clears client cache")

func production_checks() -> void:
	var network = load("res://scripts/networking/network_manager.gd").new()
	root.add_child(network)
	network._movement.initialize_navigation()
	network._ensure_deployment_ready()
	network._initialize_rebels()
	var enemy: UnitState = network._authoritative_units[1]
	enemy.position = Vector3(20,0.5,100)
	var owner := UnitState.new(100,42,Vector3(20,0.5,110))
	owner.configure(1,catalog.squad(true))
	owner.owner_player_id = 1
	network._authoritative_units[100] = owner
	network._movement.add_unit(owner)
	network._combat.add_unit(owner)
	for weapon: RuntimeWeaponInstance in owner.runtime_weapons: weapon.bind_target(AttackTarget.unit(enemy))
	var spawns: Array[Dictionary] = []
	var ends: Array[Dictionary] = []
	network.projectile_spawn_received.connect(func(row): spawns.append(row))
	network.projectile_terminal_received.connect(func(row): ends.append(row))
	var hp := enemy.health
	for frame: int in 600: network._run_server_tick(PackedInt32Array())
	check(not spawns.is_empty() and not ends.is_empty(),"production fire to flight to termination")
	check(enemy.health == hp and not network.timeline.records.any(func(row): return row.type == "shot"),"no old damage or replay shot")
	check(network._projectiles.profile.failures == 0,"no collision query failures")
	check(network._projectiles.profile.spawned == spawns.size(),"exactly one spawn per consumed emission")
	check(network.INTERNAL_STATE_REPLICATION_HZ == 10,"ten Hz internals unchanged")
	network._receive_projectile_events(spawns,ends)
	check(network.presentation.live_projectiles.is_empty(),"unauthorized local RPC rejected")
	network.free()
	await process_frame

func additional_checks() -> void:
	reset()
	var owner := UnitState.new(1,42,Vector3.ZERO)
	owner.configure(1,catalog.squad(false))
	var target := UnitState.new(2,0,Vector3(0,0,-100))
	target.configure(2,catalog.squad(false))
	var aiming := AimingSimulation.new()
	aiming.units = {1:owner,2:target}
	aiming.visibility = func(_a,_b): return true
	aiming.clear_path = func(_a,_b): return true
	aiming.moving = func(_id): return false
	aiming.target_velocities[2] = Vector3(30,0,0)
	var weapon := owner.runtime_weapons[2]
	weapon.bind_target(AttackTarget.unit(target))
	for frame: int in 120: aiming.advance(1.0/60)
	check(weapon.is_aimed and weapon.desired_yaw < 0,"actual Soldier yaw tracks lead before emission")
	var fire := FireSimulation.new()
	var shots := fire.advance(0,1,aiming)
	check(not shots.is_empty(),"ready lead produces fire event")
	if not shots.is_empty():
		check(shots[0].direction.x > 0.04 and shots[0].position != owner.position,"emission uses lead and real muzzle")
		check(shots[0].spread_radius_m == 0.15,"fixed gun spread at one hundred meters")
		var stock := weapon.inventory.duplicate()
		simulation.consume(shots)
		check(weapon.inventory == stock,"flight consumer never repeats debit")
		var projectile: ProjectileState = simulation.active.values()[0]
		var velocity := projectile.velocity
		target.position += Vector3(200,0,0)
		owner.runtime_weapons.clear()
		aiming.units.clear()
		owner = null
		target = null
		weapon = null
		simulation.advance(0.01,1)
		check(projectile.velocity == velocity and projectile.distance > 0,"target turn/source weapon removal cannot steer or stop projectile")
		check(projectile.source.unit_id == 1,"ownership safe after owning slot removed")
	reset()
	owner = UnitState.new(1,42,Vector3.ZERO)
	target = UnitState.new(2,0,Vector3(0,0,-500))
	target.configure(2,catalog.squad(false))
	owner.configure(1,catalog.squad(false))
	weapon = owner.runtime_weapons[2]
	target.position = Vector3(0,0,-500)
	weapon.bind_target(AttackTarget.unit(target))
	var friend := UnitState.new(3,42,Vector3(0,0,-10))
	friend.configure(1,catalog.vehicle("c"))
	simulation.collision.sync_units({1:owner,2:target,3:friend})
	check(not simulation.collision.fire_clear(weapon,Vector3.ZERO,Vector3(0,0,-100),{}),"normal prefire friendly blocker pauses")
	weapon.bind_target(AttackTarget.ground(Vector3(0,0,-100)))
	check(simulation.collision.fire_clear(weapon,Vector3.ZERO,Vector3(0,0,-100),{}),"forced ground skips friendly prefire check")
	friend.position = Vector3(10,0,-10)
	simulation.collision.sync_units({1:owner,2:target,3:friend})
	weapon.bind_target(AttackTarget.unit(target))
	check(simulation.collision.fire_clear(weapon,Vector3.ZERO,Vector3(0,0,-100),{}),"moving blocker updates authoritative query geometry")
	var updates: int = simulation.collision.profile.body_updates
	simulation.collision.sync_units({1:owner,2:target,3:friend})
	check(simulation.collision.profile.body_updates == updates,"unchanged bodies do not rewrite physics transforms")
	reset()
	wall("grazing",5)
	var wide := event(Vector3(0,1,2.1),Vector3(100,0,0),0.2)
	simulation.consume([wide])
	var impacts := simulation.advance(0.1,1)
	check(impacts.size() == 1,"finite projectile radius detects grazing missed by point ray")
	reset()
	for index: int in 200:
		simulation.consume([event(Vector3(0,1,0),Vector3(1,0,0),0.025,0.01)])
		simulation.advance(0.1,index)
	check(simulation.active.is_empty() and simulation.last_emission_order == 200 and simulation.profile.expired == 200,"long lifecycle leaves scalar dedup and no instances")
	check(simulation.collision.profile.query_allocations == 2,"query and sphere reused rather than per tick allocated")
	for range_m: float in [100.0,300.0]:
		var soldier := UnitState.new(50,42,Vector3.ZERO)
		soldier.configure(1,catalog.squad(false))
		var aim_target := UnitState.new(51,0,Vector3(0,0,-range_m))
		aim_target.configure(2,catalog.squad(false))
		aiming.units = {50:soldier,51:aim_target}
		aiming.target_velocities.clear()
		soldier.runtime_weapons[2].bind_target(AttackTarget.unit(aim_target))
		aiming.advance(2)
		var firing := FireSimulation.new()
		var batch := firing.advance(0,1,aiming)
		check(batch.size() == 1 and batch[0].spread_radius_m == 0.15,"gun scatter fixed at range="+str(range_m))
	var vehicle := UnitState.new(60,42,Vector3.ZERO)
	vehicle.configure(1,catalog.vehicle("a"))
	target = UnitState.new(61,0,Vector3(0,0,-900))
	target.configure(2,catalog.squad(false))
	aiming.units = {60:vehicle,61:target}
	aiming.moving = func(_id): return true
	aiming.inputs[60] = {"spread_multiplier":5.0}
	vehicle.runtime_weapons[0].bind_target(AttackTarget.unit(target))
	aiming.advance(4)
	fire = FireSimulation.new()
	shots = fire.advance(0,1,aiming)
	check(shots.size() == 1 and is_equal_approx(shots[0].spread_radius_m,shots[0].position.distance_to(target.position)/1000*2*2*5),"cannon temporary range spread times movement times personnel")
	reset()
	var single := event()
	single.consumed = 1
	single.ammo_definition_id = "cannon_a_ap"
	var recoil := event()
	recoil.consumed = 1
	recoil.ammo_definition_id = "recoilless_ap"
	var rocket := event()
	rocket.consumed = 1
	rocket.ammo_definition_id = "rocket_ap" # Explicit isolated ballistic fixture, no production assignment.
	check(simulation.consume([single,recoil,rocket]).size() == 3,"single A recoil and isolated rocket events remain one projectile each")
