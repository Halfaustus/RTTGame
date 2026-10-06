extends SceneTree

const CONFIG = preload("res://data/prototype_movement.tres")
const VEHICLE = preload("res://data/unit_mobile.tres")
const INFANTRY = preload("res://data/unit_stationary.tres")
var failures := 0
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL 0.5A: " + label)

func unit(id: int, position: Vector3, definition: UnitDefinition) -> UnitState:
	var state := UnitState.new(id,42,position)
	state.configure(1,definition)
	return state

func run() -> void:
	var simulation := MovementSimulation.new(CONFIG)
	check(simulation.initialize_navigation(PrototypeMapDefinition.new()),"navigation")
	var a := unit(1,Vector3(10,0.5,100),VEHICLE)
	var b := unit(2,Vector3(14,0.5,100),VEHICLE)
	var infantry := unit(3,a.position,INFANTRY)
	var second := unit(4,a.position,INFANTRY)
	for state: UnitState in [a,b,infantry,second]: simulation.add_unit(state)
	check(not infantry.blocks_movement() and not second.blocks_movement(),"infantry overlapping does not block")
	check(infantry.member_health.size() == INFANTRY.member_count and infantry.member_offsets.size() == infantry.member_health.size(),"member logical structure")
	var contained := true
	for offset: Vector3 in infantry.member_offsets:
		contained = contained and absf(offset.x) <= infantry.hitbox_extents().x and absf(offset.z) <= infantry.hitbox_extents().z
	check(contained,"logical members remain within aggregate hitbox")
	check(infantry.intersects_hit_segment(infantry.position - Vector3.RIGHT,infantry.position + Vector3.RIGHT),"infantry retains server hitbox while overlapping vehicle")
	check(not infantry.intersects_hit_segment(infantry.position + Vector3(0,2,0),infantry.position + Vector3(2,2,0)),"hitbox miss")
	check(simulation.translation_clear(a,a.position,Vector3(12,0.5,100)),"infantry does not block vehicle")
	b.team_id = 2
	check(not simulation.translation_clear(a,a.position,Vector3(16,0.5,100)),"swept vehicle conflict prevents tunneling")
	b.position = a.position + Vector3(0.8,0,0.8)
	check(simulation.translation_clear(a,a.position,a.position),"circular footprint permits non-overlapping diagonal centers")
	a.yaw = PI/4
	check(simulation.translation_clear(a,a.position,a.position),"footprint independent of yaw")
	a.yaw = 0
	b.position = Vector3(14,0.5,100)
	check(simulation.request_move(1,99,Vector3(16,0,100)) == "not owner","authority retained")
	check(simulation.request_move(1,42,Vector3(16,0,100)).is_empty(),"vehicle path around parked blocker")
	var separated := true
	for tick: int in 1200:
		simulation.advance(1.0/60.0)
		separated = separated and Vector2(a.position.x-b.position.x,a.position.z-b.position.z).length() >= 1.0-0.00001
		if not simulation.has_active_moves(): break
	check(separated,"vehicles remain separated")
	check(a.position.distance_to(Vector3(16,0.5,100)) < 0.001,"route reaches target")
	check(simulation.request_move(1,42,Vector3(b.position.x,0,b.position.z)).is_empty(),"occupied destination adjusted")
	check(simulation._targets[1].distance_to(b.position) >= 1.0-0.00001,"destination obeys combined radii")
	simulation.request_stop([1],42)
	a.position = Vector3(10,0.5,100)
	b.position = Vector3(30,0.5,110)
	a.yaw = -PI/2
	check(simulation.request_move(1,42,Vector3(16,0,100)).is_empty(),"unblocked original path")
	b.position = Vector3(12,0.5,100)
	simulation.advance(0.5)
	check(a.position == Vector3(10,0.5,100) and simulation.has_active_moves(),"new blocker waits retains command")
	check(b.position == Vector3(12,0.5,100),"parked blocker is not pushed")
	for tick: int in 1200:
		simulation.advance(1.0/60.0)
		if not simulation.has_active_moves(): break
	check(a.position.distance_to(Vector3(16,0.5,100)) < 0.001,"low frequency reroute")
	a.yaw = 0
	check(a.armor_direction(a.position+Vector3.FORWARD) == "front" and a.armor_direction(a.position+Vector3.RIGHT) == "side" and a.armor_direction(a.position+Vector3.BACK) == "rear","direction partition")
	a.yaw = PI/2
	check(a.armor_direction(a.position+Vector3.LEFT) == "front","authority yaw rotates armor basis")
	a.yaw = 0
	check(a.armor_direction(a.position+Vector3.FORWARD.rotated(Vector3.UP,deg_to_rad(60))) == "front" and a.armor_direction(a.position+Vector3.FORWARD.rotated(Vector3.UP,deg_to_rad(135))) == "rear","inclusive direction boundaries")
	var map := PrototypeMapDefinition.new()
	map.obstacles = [Rect2(12,98,2,4)]
	var large: UnitDefinition = VEHICLE.duplicate(true)
	large.movement_radius = 1.5
	var big := unit(5,Vector3(8,0.5,100),large)
	simulation.initialize_navigation(map)
	var nav := simulation.navigation_for(big,false)
	check(not nav.is_position_walkable(Vector3(11,0.5,100)),"per-unit radius participates in static legality")
	check(nav.segment_is_walkable(Vector3(10,0.5,95),Vector3(10,0.5,105)),"clear static segment")
	check(not nav.segment_is_walkable(Vector3(11,0.5,95),Vector3(11,0.5,105)),"swept static clearance")
	check(nav.is_position_walkable(Vector3(10.8,0.5,96.8)),"circle clears rectangle corner outside true radius")
	var narrow := PrototypeMapDefinition.new()
	narrow.obstacles = [Rect2(-20,80,80,19.4),Rect2(-20,100.6,80,19.4)]
	var waiting := MovementSimulation.new(CONFIG)
	waiting.initialize_navigation(narrow)
	var mover := unit(20,Vector3(10,0.5,100),VEHICLE)
	mover.yaw = -PI/2
	var blocker := unit(21,Vector3(14,0.5,100),VEHICLE)
	waiting.add_unit(mover)
	check(waiting.request_move(20,42,Vector3(18,0,100)).is_empty(),"corridor initial command")
	waiting.add_unit(blocker)
	for tick: int in 240: waiting.advance(1.0/60.0)
	check(waiting.has_active_moves() and mover.position.x <= 13.00001,"no bypass waits without cancelling")
	waiting.remove_unit(21)
	for tick: int in 240: waiting.advance(1.0/60.0)
	check(mover.position.distance_to(Vector3(18,0.5,100)) < 0.001,"blocker removal resumes retained route")
	var squad: UnitDefinition = INFANTRY.duplicate(true)
	squad.member_count = 8
	squad.maximum_health = 40
	check(unit(6,Vector3.ZERO,squad).member_health.size() == 8,"TEST ONLY squad count configurable, not formal N")
	squad.member_count = 6
	squad.maximum_health = 30
	check(squad.spatial_valid() and unit(7,Vector3.ZERO,squad).member_health.size() == 6,"mechanized squad structure configurable")
	infantry.health = 7.0
	infantry.synchronize_legacy_members()
	var total := 0.0
	for value: float in infantry.member_health: total += value
	check(total == infantry.health,"legacy combat aggregate and members agree")
	large.movement_radius = NAN
	check(not large.spatial_valid(),"invalid geometry rejected")
	var spawned_model = load("res://scripts/networking/network_manager.gd").new()
	root.add_child(spawned_model)
	spawned_model._ensure_deployment_ready()
	spawned_model._movement.initialize_navigation()
	spawned_model.deployment.register_player(1,1,0)
	spawned_model._peer_players[42] = 1
	var purchase: Dictionary = spawned_model.deployment.buy_order(1,"test.rifle","ground.west")
	check(purchase.ok and spawned_model.deployment.place_order(1,purchase.order_id,Vector3(10,0,110)).ok,"deployment request retained")
	for tick: int in 3*spawned_model.timeline.tick_hz: spawned_model._run_server_tick(PackedInt32Array([42]))
	var row: Dictionary = spawned_model.deployment._orders[purchase.order_id]
	check(row.status == "generated","production spawning")
	var generated: UnitState = spawned_model._authoritative_units[row.unit_id]
	check(generated.member_health.size() == generated.definition.member_count and generated.intersects_hit_segment(generated.position-Vector3.RIGHT,generated.position+Vector3.RIGHT),"deployment initializes squad and hitbox")
	check(generated.owner_player_id == 1 and generated.owner_peer_id == 42,"match and connection identity preserved")
	spawned_model.timeline.begin_tick()
	spawned_model.timeline.enter_phase("session")
	spawned_model._apply_peer_join(77)
	var free_found := false
	for state: UnitState in spawned_model._authoritative_units.values():
		if state.owner_peer_id == 77 and state.unit_type() == UnitDefinition.UnitType.INFANTRY:
			free_found = state.member_health.size() == state.definition.member_count and state.definition.configuration_source.begins_with("test_only:")
	check(free_found,"free spawning initializes same squad structure")
	spawned_model.free()
	print("0.5A checks=",checks," failures=",failures)
	quit(1 if failures else 0)
