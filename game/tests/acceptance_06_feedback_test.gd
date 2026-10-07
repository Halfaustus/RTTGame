extends "res://tests/db29_combat_timeline_test.gd"

func run() -> void:
	var manager = load("res://scripts/networking/network_manager.gd").new()
	root.add_child(manager)
	manager._peer_players[42] = 1
	var event := {"position":Vector3(3,0.5,4),"radius":4.0,"hit_unit_id":123,"damage":99}
	check(manager._replication_arguments_for_peer("_receive_acceptance_explosion",[event],42).is_empty(),"visual disabled outside acceptance")
	manager.acceptance_full_06 = true
	var permitted: Array = manager._replication_arguments_for_peer("_receive_acceptance_explosion",[event],42)
	check(permitted.size() == 1 and permitted[0].size() == 2 and not permitted[0].has("hit_unit_id"),"range visualization projects only point/radius")
	check(manager._replication_arguments_for_peer("_receive_acceptance_explosion",[event],43).is_empty(),"unbound peer denied")
	check(manager.acceptance_explosion_arguments([{"position":Vector3.ZERO,"radius":-1}]).is_empty(),"invalid radius denied")
	var visual := TemporaryExplosionVisual.new()
	root.add_child(visual)
	visual.show_event(permitted[0])
	visual._process(0.1)
	check(visual.flashes.size() == 1 and visual.mesh.get_surface_count() == 1,"actual range mesh created")
	visual._process(2)
	check(visual.flashes.is_empty() and visual.mesh.get_surface_count() == 0,"range mesh expires")
	var feed := PresentationFeed.new()
	var world = load("res://scenes/maps/db33_active_test_world.tscn").instantiate()
	world.presentation_source = feed
	root.add_child(world)
	world._on_unit_spawn_received(901,42,Vector3.ZERO)
	world._selected_units[901] = world._visual_units[901]
	world._selection_collection[901] = world._visual_units[901]
	world._on_unit_identity_received(901,1,"res://data/units/acceptance_06c_suppression.tres")
	check(world._unit_markers[901].temporary_role == "suppression","identity selects distinct temporary badge")
	world._on_unit_combat_state_received(901,1,60,0)
	check(not world._visual_units.has(901) and not world._unit_markers.has(901) and world._selected_units.is_empty() and world._selection_collection.is_empty(),"authoritative zero HP removes body/badge/selection")
	world._on_unit_spawn_received(901,42,Vector3.ZERO)
	check(not world._visual_units.has(901),"duplicate snapshot cannot revive dead unit")
	for name: String in ["normal","top","suppression","modules","infantry"]:
		var definition: UnitDefinition = load("res://data/units/acceptance_06c_%s.tres" % name)
		check(definition.member_count == 12 and definition.maximum_health == 60,"test squad retains five health per member "+name)
	world.free()
	visual.free()
	manager.free()
	print("06 FEEDBACK: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
