extends SceneTree

const INF = preload("res://data/unit_stationary.tres")
const SIX = preload("res://data/unit_mechanized_05b.tres")
const VEH = preload("res://data/unit_mobile.tres")
const CONFIG = preload("res://data/prototype_movement.tres")
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL 0.5B: " + label)
func unit(id: int, definition: UnitDefinition) -> UnitState:
	var state := UnitState.new(id,42,Vector3(10,0.5,100))
	state.configure(1,definition)
	return state
func run() -> void:
	var squad := unit(1,INF)
	var six := unit(2,SIX)
	check(squad.members.size() == 8 and squad.maximum_health == 40 and squad.health == 40,"formal eight-person squad")
	check(six.members.size() == 6 and six.maximum_health == 30,"formal six-person squad")
	check(squad.members[0] != squad.members[1] and squad.members[0].health == 5,"independent HP objects")
	squad.members[0].health = 2
	check(squad.health == 37 and squad.members[1].health == 5,"derived aggregate HP")
	check(squad.members[0].position != squad.members[1].position,"independent server positions")
	var soldier := squad.members[0]
	check(soldier.intersects_hit_segment(soldier.position-Vector3.RIGHT,soldier.position+Vector3.RIGHT),"individual hitbox")
	check(not soldier.intersects_hit_segment(soldier.position+Vector3.UP,soldier.position+Vector3.UP+Vector3.RIGHT),"individual hitbox miss")
	check(soldier.weapon_slots.is_empty(),"weapon assignment foundation without invented loadout")
	check(squad.hit_members(soldier.position-Vector3.RIGHT,soldier.position+Vector3.RIGHT).has(soldier.member_id),"squad exposes member hit identities")
	var generated := true
	for count: int in range(1,17):
		var slots := SquadFormation.slots(count,0.5)
		generated = generated and slots.size() == count and slots == SquadFormation.slots(count,0.5)
	check(generated and SquadFormation.slots(0,0.5).is_empty(),"parameterized deterministic formation")
	var old_position := soldier.position
	squad.position += Vector3.RIGHT*2
	check(squad.advance_members(0.1) and soldier.position != old_position,"authoritative actual following")
	check(soldier.position.distance_to(old_position) <= INF.unhardened_speed*INF.member_follow_speed_multiplier*0.1+0.00001,"bounded following rather than teleport")
	check(soldier.position != squad.position+squad.formation_slots[0],"member can lag anchor")
	check(squad.hit_members(soldier.position-Vector3.UP,soldier.position+Vector3.UP).has(soldier.member_id),"lagging member not discarded by anchor box")
	squad.members[2].health = 0
	squad.advance_members(0)
	var assigned: Array[int] = []
	for member: SoldierState in squad.members:
		if member.health > 0: assigned.append(member.formation_slot)
	check(assigned == [0,1,2,3,4,5,6] and squad.members[2].formation_slot == -1,"death reassigns without holes")
	check(squad.formation_slots.size() == 7 and squad.members[3].formation_slot == 2,"members not permanently tied to numbered slot")
	check(not squad.members[2].intersects_hit_segment(squad.members[2].position-Vector3.RIGHT,squad.members[2].position+Vector3.RIGHT),"dead member excluded from hit query")
	var adapter := unit(3,INF)
	adapter.apply_prototype_damage(10)
	check(adapter.health == 35 and adapter.members[0].health == 0 and adapter.members[1].health == 5,"legacy shot adapter no overflow to another person")
	adapter.health = 5
	adapter.apply_prototype_damage(10)
	check(adapter.health == 0 and adapter.formation_slots.is_empty(),"last member determines squad death")
	var simulation := MovementSimulation.new(CONFIG)
	check(simulation.initialize_navigation(),"navigation initialized")
	var vehicle := unit(4,VEH)
	var overlap := unit(5,INF)
	simulation.add_unit(vehicle)
	simulation.add_unit(overlap)
	check(simulation.translation_clear(vehicle,vehicle.position,vehicle.position+Vector3.RIGHT),"soldiers do not block hull")
	check(simulation.request_move(5,42,Vector3(14,0,100)).is_empty(),"squad remains command subject")
	check(simulation.request_move(500,42,Vector3(14,0,100)) == "unknown unit","members not registered as commandable units")
	var before := overlap.members[0].position
	simulation.advance(0.1)
	check(overlap.members[0].position != before,"movement system advances soldiers")
	check(vehicle.mounts.is_empty() and vehicle.blocks_movement(),"zero mounts leaves hull geometry intact")
	var definition: UnitDefinition = VEH.duplicate(true)
	var hull_slot := WeaponSlotDefinition.new()
	hull_slot.slot_id = "hull.test"
	definition.hull_weapon_slots = [hull_slot]
	var main := WeaponMountDefinition.new()
	main.mount_id = "main"
	var main_slot := WeaponSlotDefinition.new()
	main_slot.slot_id = "main.test"
	main.weapon_slots = [main_slot]
	definition.mounts = [main]
	var mounted := unit(6,definition)
	check(mounted.mounts.size() == 1 and mounted.mounts[0].kind == WeaponMountDefinition.Kind.MAIN_TURRET,"single main turret")
	check(mounted.mounts[0].world_yaw == mounted.yaw,"default mount initially aligned")
	var station := WeaponMountDefinition.new()
	station.mount_id = "station"
	station.kind = WeaponMountDefinition.Kind.WEAPON_STATION
	station.initial_relative_yaw = PI/2
	var other: WeaponMountDefinition = station.duplicate(true)
	other.mount_id = "second_station"
	definition.mounts = [main,station,other]
	mounted = unit(7,definition)
	check(mounted.mounts.size() == 3 and mounted.mounts[2].kind == WeaponMountDefinition.Kind.WEAPON_STATION,"multiple mounts and stations")
	check(is_equal_approx(mounted.mounts[1].world_yaw,PI/2),"configured initial relative yaw")
	mounted.mounts[0].world_yaw = -PI/2
	mounted.yaw = PI/4
	check(mounted.mounts[0].world_yaw != mounted.yaw and mounted.mounts[1].world_yaw != mounted.mounts[0].world_yaw,"independent authoritative mount facing")
	check(is_equal_approx(mounted.mounts[0].relative_yaw(mounted.yaw),-PI/2),"relative hull relationship retained by DB17 transform")
	check(mounted.slot_world_yaw() == mounted.yaw and is_equal_approx(mounted.slot_world_yaw("main"),-PI/4),"weapon slots use composed owner facing")
	check(mounted.hull_weapon_slots[0].slot_id == "hull.test" and mounted.mounts[0].weapon_slots[0].slot_id == "main.test","slot ownership")
	var forbidden := false
	for property: Dictionary in mounted.mounts[0].get_property_list():
		forbidden = forbidden or property.name in ["health","hitbox","hitbox_half_extents","movement_radius","position"]
	check(not forbidden,"mount has no independent entity geometry or HP")
	check(mounted.movement_radius() == vehicle.movement_radius() and mounted.hitbox_extents() == vehicle.hitbox_extents(),"mount does not change hull geometry")
	check(mounted.armor_direction(mounted.position+Vector3.FORWARD.rotated(Vector3.UP,mounted.yaw)) == "front","armor uses hull not mount")
	var feed := PresentationFeed.new()
	var structure := squad.structure_snapshot()
	feed.apply_live_structure(structure)
	structure.members[0].health = 0
	check(feed.live_structures[1].members[0].health == 2,"network presentation stores independent server snapshot")
	feed.unit_death_received.emit(1)
	check(feed.live_structures.is_empty(),"death clears live internal state")
	check(not squad.snapshot().has("members") and not mounted.snapshot().has("mounts"),"v1 representation remains aggregate")
	var network = load("res://scripts/networking/network_manager.gd").new()
	root.add_child(network)
	network._ensure_deployment_ready()
	network._movement.initialize_navigation()
	network._initialize_rebels()
	var valid_enemy := true
	for state: UnitState in network._authoritative_units.values(): valid_enemy = valid_enemy and state.members.size() == 8 and state.members[0].position.distance_to(state.position) < 2
	check(valid_enemy,"enemy production initialization")
	network.deployment.register_player(1,1,0)
	network._peer_players[42] = 1
	var purchase: Dictionary = network.deployment.buy_order(1,"test.rifle","ground.west")
	check(purchase.ok and network.deployment.place_order(1,purchase.order_id,Vector3(10,0,110)).ok,"purchase placement")
	for tick: int in 180: network._run_server_tick(PackedInt32Array([42]))
	var row: Dictionary = network.deployment._orders[purchase.order_id]
	check(row.status == "generated","order completes")
	var bought: UnitState = network._authoritative_units[row.unit_id]
	check(bought.members.size() == 8 and bought.health == 40 and bought.members[0].position.distance_to(bought.position) < 2,"purchased members initialized at real spawn")
	network.timeline.begin_tick()
	network.timeline.enter_phase("session")
	network._apply_peer_join(77)
	var free_valid := false
	for state: UnitState in network._authoritative_units.values():
		if state.owner_peer_id == 77 and state.unit_type() == UnitDefinition.UnitType.INFANTRY: free_valid = state.members.size() == 8
	check(free_valid,"free production initialization")
	var free_vehicle_valid := false
	for state: UnitState in network._authoritative_units.values():
		if state.owner_peer_id == 77 and state.unit_type() == UnitDefinition.UnitType.ARMORED_VEHICLE:
			free_vehicle_valid = state.members.is_empty() and state.mounts.size() == 2 and state.blocks_movement()
	check(free_vehicle_valid,"free hull initialized with confirmed 0.5D mount loadout")
	network.timeline.enter_phase("replication")
	network.timeline.finish_tick()
	var armor: Dictionary = network.deployment.buy_order(1,"test.armored","ground.west")
	check(armor.ok and network.deployment.place_order(1,armor.order_id,Vector3(14,0,110)).ok,"armor purchase placement")
	for tick: int in 180: network._run_server_tick(PackedInt32Array([42]))
	var armor_row: Dictionary = network.deployment._orders[armor.order_id]
	check(armor_row.status == "generated","armor order completes")
	var bought_armor: UnitState = network._authoritative_units[armor_row.unit_id]
	check(bought_armor.members.is_empty() and bought_armor.blocks_movement() and bought_armor.intersects_hit_segment(bought_armor.position-Vector3.RIGHT,bought_armor.position+Vector3.RIGHT),"purchased hull geometry")
	network._receive_unit_structures([squad.structure_snapshot()])
	check(network.presentation.live_structures.is_empty(),"structure RPC rejects unauthenticated local authority")
	network.free()
	var frozen := ReplayFormat.read_file("res://tests/fixtures/replay_v1.json")
	var document: Dictionary = frozen.document.duplicate(true)
	document.header.rules_id = ReplayContent.RULES_ID
	document.header.map_id = ReplayContent.MAP_ID
	document.header.content_fingerprints = ReplayContent.fingerprints()
	check(ReplayContent.compatibility(document).is_empty(),"current replay rules and manifest")
	document.header.rules_id = ReplayContent.LEGACY_RULES_ID
	check(ReplayContent.compatibility(document).is_empty(),"explicit legacy rules support")
	document.header.rules_id = "unknown"
	check(not ReplayContent.compatibility(document).is_empty(),"unknown replay rules rejected")
	document.header.rules_id = ReplayContent.RULES_ID
	document.header.content_fingerprints.clear()
	check(not ReplayContent.compatibility(document).is_empty(),"empty manifest cannot bypass compatibility")
	check(not ReplayContent.compatibility({}).is_empty(),"invalid document fails clearly")
	print("0.5B checks=",checks," failures=",failures)
	quit(1 if failures else 0)
