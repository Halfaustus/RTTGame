extends SceneTree

var checks := 0
var failures := 0
var catalog := Prototype05DCatalog.new()
var aiming: AimingSimulation
var fire: FireSimulation
var shooter: UnitState
var victim: UnitState
var weapon: RuntimeWeaponInstance
var tick_id := 0
var visible := true
var moving := false
var clear := true
var events: Array[Dictionary] = []

func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL 0.5E: "+label)
func setup(id: String, stock: Dictionary = {}) -> void:
	aiming = AimingSimulation.new()
	fire = FireSimulation.new()
	tick_id = 0
	events.clear()
	visible = true
	moving = false
	clear = true
	aiming.visibility = func(_a,_b): return visible
	aiming.clear_path = func(_a,_b): return clear
	aiming.moving = func(_id): return moving
	var definition := UnitDefinition.new()
	definition.member_count = 1
	var inventory: Dictionary = stock if not stock.is_empty() else catalog.default_inventory.get(id,{})
	if inventory.is_empty(): inventory = {"recoilless_ap":4,"recoilless_he":4} if id == "recoilless" else {"rocket_ap":2}
	catalog.allocate(definition,id,WeaponAllocation.NodeKind.SOLDIER,"1","primary",inventory)
	shooter = UnitState.new(1,42,Vector3.ZERO)
	shooter.configure(1,definition)
	victim = UnitState.new(2,0,Vector3(0,0,-100))
	victim.configure(2,catalog.squad(true))
	aiming.units = {1:shooter,2:victim}
	weapon = shooter.runtime_weapons[0]
	weapon.bind_target(AttackTarget.unit(victim))
	# Explicit ready-aim fixture: flow tests separate from real Aiming tests below.
	weapon.aim_progress = 1
	weapon.aim_timer_complete = true
	weapon.orientation_ready = true
	weapon.is_aimed = true
func step(delta: float, real_aim: bool = false) -> Array[Dictionary]:
	if real_aim: aiming.advance(delta)
	var emitted := fire.advance(delta,tick_id,aiming)
	tick_id += 1
	events.append_array(emitted)
	return emitted
func run() -> void:
	setup("rifle")
	var hp := victim.health
	var ammo: int = weapon.inventory.standard
	check(step(0).size() == 1,"first ready emission")
	check(weapon.inventory.standard == ammo-3 and weapon.pending_rounds == 27,"one event consumes three stock and pending")
	check(events[0].consumed == 3 and not events[0].has("health") and not events[0].has("damage"),"event carries consumption no applied damage")
	check(fire.advance(99,0,aiming).is_empty() and weapon.inventory.standard == 147,"duplicate tick no time or debit replay")
	check(step(1.49).is_empty() and step(0.01).size() == 1,"one point five second interval")
	check(victim.health == hp,"emission has no damage")
	var before := weapon.inventory.duplicate()
	weapon.enabled = false
	check(step(10).is_empty() and weapon.inventory == before,"disabled blocks ready aim")
	weapon.enabled = true
	visible = false
	check(step(1).is_empty() and weapon.fire_state.reason == "not_visible","fresh visibility check before commit")
	visible = true
	clear = false
	check(step(1).is_empty() and weapon.fire_state.reason == "path_blocked","fresh path check")
	clear = true
	aiming.inputs[1] = {"return_fire_locked":true}
	check(step(1).is_empty(),"only retaliate permission")
	aiming.inputs.clear()
	weapon.is_aimed = false
	check(step(1).is_empty() and weapon.fire_state.reason == "not_aimed","aim incomplete")
	weapon.is_aimed = true
	victim.position = Vector3(100,0,0)
	check(step(1).is_empty(),"actual direction rechecked, stale aim refused")
	victim.position = Vector3(0,0,-401)
	check(step(1).is_empty() and weapon.fire_state.reason == "out_of_range","fresh range check")
	setup("rifle",{"standard":4})
	step(0)
	check(weapon.inventory.standard == 1 and weapon.pending_rounds == 1 and weapon.fire_state.loading,"partial magazine starts loading after complete triplet")
	check(step(3).is_empty() and weapon.inventory.standard == 1 and weapon.pending_rounds == 1,"partial stock cannot emit residual rounds")
	weapon.inventory.standard = 5
	check(step(0).is_empty() and weapon.fire_state.reason == "pending_recovery_undefined","undefined exhausted-stock recovery explicitly blocked")
	setup("rifle")
	step(0)
	for index: int in 9: step(1.5)
	check(events.size() == 10 and is_equal_approx(events[-1].time_seconds,13.5),"ten triplets first magazine at thirteen point five")
	check(weapon.inventory.standard == 120 and weapon.pending_rounds == 0,"total stock includes magazine")
	step(1.5)
	check(events.size() == 10 and weapon.fire_state.loading_progress == 0.5,"interval and loading progress in parallel")
	step(1.5)
	check(events.size() == 11 and is_equal_approx(events[-1].time_seconds,16.5),"next magazine first at sixteen point five, not eighteen")
	check(weapon.inventory.standard == 117 and weapon.pending_rounds == 27,"reload no duplicate ammunition")
	setup("recoilless")
	step(0)
	check(events.size() == 1 and weapon.pending_rounds == 0,"per round gun consumes one")
	step(5.99)
	check(events.size() == 1,"six seconds gun prep not early")
	step(0.01)
	check(events.size() == 2 and is_equal_approx(events[1].time_seconds,6),"six seconds gun next emission")
	check(weapon.aim_progress == 1,"same target no re-aim after fire")
	setup("rocket")
	step(0)
	check(step(2.99).is_empty() and step(0.01).size() == 1,"isolated launcher prepares next in three seconds")
	setup("recoilless")
	step(0)
	weapon.enabled = false
	step(3)
	check(weapon.fire_state.loading_progress == 0.5,"disabled still loads")
	aiming.inputs[1] = {"personnel_load_multiplier":2.0,"loading_module_multiplier":2.0}
	step(3)
	check(is_equal_approx(weapon.fire_state.loading_progress,0.625),"manual state and module multiply with retained percentage")
	aiming.inputs[1] = {"personnel_load_multiplier":5.0}
	step(3)
	check(is_equal_approx(weapon.fire_state.loading_progress,0.725),"incapacitated still prepares with retained percentage")
	var retained := weapon.fire_state.loading_progress
	weapon.bind_target(AttackTarget.unit(victim))
	check(weapon.fire_state.loading_progress == retained,"target binding does not reset loading")
	weapon.inventory.recoilless_ap += 10
	check(weapon.fire_state.loading_progress == retained,"stock replenishment cannot shorten timer")
	setup("rifle")
	weapon.fire_state.loading = true
	weapon.fire_state.loading_progress = 0
	weapon.pending_rounds = 0
	weapon.reset_aim()
	for index: int in 30: step(0.1,true)
	check(events.size() == 1,"real aiming and reload parallel, not serial")
	setup("recoilless")
	moving = true
	check(step(1).is_empty() and weapon.fire_state.reason == "moving_prohibited","moving permission revalidated")
	setup("rifle")
	check(step(60).size() == 1 and weapon.inventory.standard == 147,"large dt no historical burst")
	check(step(0).is_empty(),"zero dt cannot bypass interval")
	selection_checks()
	extra_checks()
	vehicle_checks()
	timing_checks()
	await network_checks()
	print("0.5E: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func extra_checks() -> void:
	setup("recoilless")
	step(0)
	weapon.inventory.recoilless_ap = 0
	var progress := weapon.aim_progress
	var switched := step(6)
	check(switched.size() == 1 and switched[0].ammo_definition_id == "recoilless_he","ammo chosen at emission after inventory changed during preparation: "+weapon.fire_state.reason)
	check(weapon.aim_progress == progress and weapon.fire_state.loading_progress == 0,"ammo switch does not restart aim or add switching delay")
	setup("rifle")
	check(step(-1).is_empty() and fire.last_tick == -1,"invalid dt no authority advancement")
	aiming.inputs[1] = {"sprinting":true}
	check(step(0).is_empty() and weapon.fire_state.reason == "sprinting","sprint blocks firing")
	aiming.inputs.clear()
	victim.team_id = shooter.team_id
	check(step(0).is_empty() and weapon.fire_state.reason == "friendly_target","friendly target blocks firing")
	victim.team_id = 2
	weapon.definition = weapon.definition.duplicate()
	weapon.definition.allowed_target_types = [WeaponDefinition.TargetType.GROUND_VEHICLE]
	check(step(0).is_empty() and weapon.fire_state.reason == "type_not_allowed","explicit type restriction")
	setup("rifle")
	victim.health = 0
	check(step(0).is_empty() and weapon.inventory.standard == 150,"destroyed target cannot consume inventory")
	setup("rifle")
	var vehicle := UnitState.new(3,42,Vector3.ZERO)
	vehicle.configure(1,catalog.weapon_slot_fixture("b"))
	aiming.units[3] = vehicle
	for instance: RuntimeWeaponInstance in vehicle.runtime_weapons:
		instance.bind_target(AttackTarget.unit(victim))
		instance.aim_progress = 1
		instance.aim_timer_complete = true
		instance.is_aimed = true
	var batch := step(0)
	check(batch.size() == 4,"rifle and three independently ready vehicle weapons emit together")
	check(vehicle.runtime_weapons[0].pending_rounds == 27 and vehicle.runtime_weapons[1].pending_rounds == 447,"B cannon and coax debit three from different capacities")
	vehicle.runtime_weapons[1].enabled = false
	var coax_stock := vehicle.runtime_weapons[1].inventory.duplicate()
	step(1.5)
	check(vehicle.runtime_weapons[1].inventory == coax_stock and vehicle.runtime_weapons[0].fire_state.emission_count == 2,"shared mount does not share enabled state or firing timers")

func selection_checks() -> void:
	check(is_equal_approx(AmmoSelection.penetration(catalog.ammunition.standard,0),12),"rifle near anchor")
	check(AmmoSelection.penetration(catalog.ammunition.standard,400) == 5 and AmmoSelection.penetration(catalog.ammunition.standard,500) == 5 and AmmoSelection.penetration(catalog.ammunition.standard,600) == 5,"shared rifle LMG curve endpoint and plateau")
	check(AmmoSelection.penetration(catalog.ammunition.pdw,200) == 5,"PDW anchor")
	check(AmmoSelection.expected_damage(catalog.ammunition.standard,12,6,0,0) == 1,"combined damage not multiplied by three")
	check(AmmoSelection.expected_damage(catalog.ammunition.standard,5,10,0,0) == 0,"kinetic half armor threshold")
	check(is_equal_approx(AmmoSelection.expected_damage(catalog.ammunition.recoilless_ap,400,400,0,0),4),"chemical formal formula preview only")
	check(is_equal_approx(AmmoSelection.expected_damage(catalog.ammunition.standard,12,6,0.5,0.5),0.75),"proportional cover and ignore")
	setup("recoilless")
	var selection := AmmoSelection.select(weapon,{"cover_reductions":[0.2,0.5]})
	check(selection.ammo.ammo_id == "recoilless_ap","current expected damage winner")
	var first: AmmoDefinition = weapon.definition.ammo_definitions[0].duplicate()
	var second: AmmoDefinition = first.duplicate()
	second.ammo_id = "tie_second"
	weapon.definition = weapon.definition.duplicate()
	weapon.definition.ammo_definitions = [first,second]
	weapon.inventory = {first.ammo_id:1,second.ammo_id:100}
	check(AmmoSelection.select(weapon,{}).ammo == first,"first tie uses configuration order, not stock amount")
	weapon.fire_state.last_ammo_id = second.ammo_id
	check(AmmoSelection.select(weapon,{}).ammo == second,"equal damage retains previous ammo")
	weapon.inventory[second.ammo_id] = 0
	check(AmmoSelection.select(weapon,{}).ammo == first,"empty previous ammo excluded")
	setup("rifle")
	weapon.definition = weapon.definition.duplicate(true)
	weapon.definition.ammo_definitions[0].test_curve = ""
	check(step(0).is_empty() and weapon.fire_state.reason == "selection_configuration_missing" and weapon.inventory.standard == 150,"missing curve refuses atomic emission")
	setup("rifle")
	weapon.definition = weapon.definition.duplicate()
	weapon.definition.reduction_ignore = -1
	check(step(0).is_empty() and weapon.inventory.standard == 150,"unknown reduction ignore cannot silently default")

func vehicle_checks() -> void:
	setup("rifle")
	var vehicle := UnitState.new(3,42,Vector3.ZERO)
	vehicle.configure(1,catalog.weapon_slot_fixture("a"))
	aiming.units[3] = vehicle
	weapon = vehicle.runtime_weapons[0]
	weapon.bind_target(AttackTarget.unit(victim))
	weapon.is_aimed = true
	weapon.aim_timer_complete = true
	step(0)
	for index: int in 9: step(1)
	check(weapon.fire_state.emission_count == 10 and weapon.pending_rounds == 0,"A ten independent single rounds")
	weapon.enabled = false
	aiming.inputs[3] = {"personnel_load_multiplier":5.0,"loading_module_multiplier":2.0}
	step(4)
	check(is_equal_approx(weapon.fire_state.loading_progress,0.5),"mechanical loading ignores personnel, uses module")
	aiming.inputs[3] = {}
	step(2)
	check(weapon.fire_state.loading_progress == 1 and weapon.pending_rounds == 10,"module change retains completion percentage")
	check(victim.health == 40,"vehicle emissions no damage")
	var defense := UnitState.new(4,42,Vector3.ZERO)
	defense.configure(1,catalog.squad(false))
	check(defense.runtime_weapons.size() == 8 and defense.unassigned_inventory.rocket_ap == 5,"unassigned rockets never instantiate")
	var other := UnitState.new(5,42,Vector3.ZERO)
	other.configure(1,vehicle.definition)
	check(other.runtime_weapons[0].pending_rounds == 10 and other.runtime_weapons[0].fire_state.loading_progress == 1 and other.runtime_weapons[0].inventory == {"cannon_a_ap":10,"cannon_a_he":40},"shared definitions independent flow and stock")
	var feed := PresentationFeed.new()
	var received: Array[Dictionary] = []
	feed.weapon_fire_received.connect(func(event): received.append(event))
	feed.apply_fire_event(events[0])
	feed.apply_fire_event(events[0])
	check(received.size() == 1,"presentation event dedup no repeated debit")
	check(received[0].position is Vector3 and received[0].target_position is Vector3 and received[0].event_id is String,"stable event spatial contract")

func timing_checks() -> void:
	for dt: float in [0.1,0.05,1.0/60]:
		setup("rifle")
		step(0)
		for index: int in roundi(18/dt): step(dt)
		check(events.size() == 12 and is_equal_approx(events[10].time_seconds,16.5),"cadence reload endpoints dt="+str(dt))
		var unique := {}
		for event: Dictionary in events: unique[event.event_id] = true
		check(unique.size() == events.size() and weapon.inventory.standard == 114,"stable unique events dt="+str(dt))

func network_checks() -> void:
	var network = load("res://scripts/networking/network_manager.gd").new()
	root.add_child(network)
	network._movement.initialize_navigation()
	network._ensure_deployment_ready()
	network._initialize_rebels()
	network._peer_players[42] = 1
	network.deployment.register_player(1,1,0)
	var state := UnitState.new(100,42,Vector3(20,0.5,110))
	state.owner_player_id = 1
	state.configure(1,preload("res://data/05d/assault.tres"))
	network._authoritative_units[100] = state
	network._movement.add_unit(state)
	network._combat.add_unit(state)
	var enemy: UnitState = network._authoritative_units[1]
	# Place the existing enemy on a verified clear test lane; retain real LOS checks.
	enemy.position = Vector3(20,0.5,100)
	var stock_before := state.runtime_weapons[2].inventory.duplicate()
	for instance: RuntimeWeaponInstance in state.runtime_weapons: instance.bind_target(AttackTarget.unit(enemy))
	var emitted: Array[Dictionary] = []
	network.weapon_fire_received.connect(func(event): emitted.append(event))
	var hp := enemy.health
	for index: int in 1200: network._run_server_tick(PackedInt32Array([42]))
	check(emitted.is_empty() and state.runtime_weapons[2].inventory == stock_before,"unobserved production enemy is not firing permission")
	check(enemy.health == hp and not network.timeline.records.any(func(row): return row.type == "shot"),"no old damage or replay shot side effects")
	check(network.INTERNAL_STATE_REPLICATION_HZ == 10 and state.structure_snapshot().weapons[2].has("fire"),"existing ten Hz flow state replication")
	var before: int = network.presentation._fire_sequences.size()
	network._receive_weapon_fires(emitted)
	check(network.presentation._fire_sequences.size() == before,"unauthenticated local RPC rejected")
	network.free()
	await process_frame
