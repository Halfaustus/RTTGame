extends "res://tests/prototype_06c_test.gd"

func run() -> void:
	var defs: Array[UnitDefinition] = []
	for path: String in ["normal","top","infantry","armor"]:
		var definition: UnitDefinition = load("res://data/units/acceptance_06c_%s.tres" % path)
		check(definition.configuration_source.begins_with("test_only:rtt_unit_editor:"),"editor provenance "+path)
		check(UnitDefinitionValidator.validate_unit_definition(definition).implemented_combat_ready,"current combat schema "+path)
		defs.append(definition)
	check(not defs[0].weapon_allocations[0].definition.attack_top and defs[1].weapon_allocations[0].definition.attack_top,"independent normal/top fixtures")
	var preview := ArtilleryPreview.new()
	for definition: UnitDefinition in [defs[0],defs[1]]:
		var weapon: WeaponDefinition = definition.weapon_allocations[0].definition
		var view := {"definition_id":weapon.definition_id,"weapon_position":Vector3(0,0.5,100),"muzzle_position":Vector3(0,0.5,100),"inventory":definition.weapon_allocations[0].initial_inventory}
		check(preview.describe(view,Vector3(0,0,96),false).is_empty(),"unknown fixture not implicitly granted preview")
		preview.test_definitions[weapon.definition_id] = weapon
		check(preview.describe(view,Vector3(0,0,96),false).get("valid",false),"editor fixture direct preview resolves actual ammo")
		check(preview.describe(view,Vector3(0,0,96),true).is_empty(),"editor direct fixture not artillery")
	preview.free()
	var manager = load("res://scripts/networking/network_manager.gd").new()
	root.add_child(manager)
	check(manager.configure_active_test_map() and manager.configure_acceptance_06c(),"opt-in configuration")
	manager._initialize_rebels()
	check(manager._authoritative_units.size() == 3,"real enemy infantry and armor instances")
	manager._peer_players[42] = 1
	for id: int in manager._authoritative_units:
		var state: UnitState = manager._authoritative_units[id]
		check(state.owner_peer_id == 0 and state.team_id == 2,"enemy server ownership")
		check(not manager._replication_arguments_for_peer("_receive_unit_snapshot",[manager._presentation_snapshot(state)],42).is_empty(),"known fixture public snapshot")
		check(manager._replication_arguments_for_peer("_receive_unit_structures",[[{"unit_id":id}]],42).is_empty(),"private enemy members never disclosed")
	manager.acceptance_06c = false
	check(manager._replication_arguments_for_peer("_receive_unit_snapshot",[manager._presentation_snapshot(manager._authoritative_units[1])],42).is_empty(),"default mode enemy filtering unchanged")
	manager.acceptance_06c = true
	check(manager._ensure_deployment_ready(),"actual catalog initialization")
	check(manager.deployment._config.catalog.size() == 3,"three usable editor catalog entries")
	manager._peer_players.clear()
	manager.timeline.begin_tick()
	manager.timeline.enter_phase("session")
	manager._apply_peer_join(42)
	manager.timeline.enter_phase("replication")
	manager.timeline.finish_tick()
	check(manager._authoritative_units.size() == 6 and manager._authoritative_units[6].unit_type() == UnitDefinition.UnitType.ARMORED_VEHICLE,"each player receives normal/top/armor")
	var command := {"type":"ground_fire","unit_ids":[4],"player_id":1,"peer_id":42,"target":Vector3(-3,0,96),"count":1,"group":false,"mode":-1,"facing":Vector3.ZERO}
	var accepted: Dictionary = manager._execute_command(command)
	check(accepted.unit_ids == [4],"real G command accepts own editor weapon")
	command.unit_ids = [2]
	check(manager._execute_command(command).unit_ids.is_empty(),"enemy command authorization rejected")
	for tick: int in 55: manager._run_server_tick(PackedInt32Array([42]))
	check(manager._authoritative_units[2].health < manager._authoritative_units[2].maximum_health and not manager._combat_timeline.halted,"real server step emits, settles and observes editor damage")
	var test := fixture(1)
	test.unit.configure(1,defs[0])
	test.unit.position = Vector3(0,0.5,0)
	test.target.configure(2,defs[3])
	test.target.position = Vector3(0,0.5,-30)
	test.unit.runtime_weapons[0].bind_single_ground_target(test.target.position)
	test.aiming.advance(3.0)
	test.timeline.direct_hit_enabled = true
	var actual: Array = []
	for step: int in 40:
		var result: Dictionary = test.timeline.step(test.aiming)
		actual.append_array(result.get("damage_results",[]))
	check(not test.timeline.halted and not actual.is_empty(),"editor weapon actual firing/flight/impact settlement")
	check(actual.size() == 1 and actual[0].member_id == 0 and actual[0].health_after < actual[0].health_before,"one hull damage record per shot")
	var scene := load("res://scenes/units/unit.tscn")
	var infantry: Node3D = scene.instantiate()
	root.add_child(infantry)
	check(infantry.get_node("MeshInstance3D").mesh == null and not infantry.get_node("MeshInstance3D").visible,"active infantry model detached")
	check(infantry.get_node("PickBody") != null,"selection collider retained")
	infantry.display_unit_type(UnitDefinition.UnitType.ARMORED_VEHICLE)
	check(infantry.get_node("MeshInstance3D").mesh.size == Vector3(0.6,0.08,0.8),"armor rectangle")
	infantry.legacy_model_binding = true
	infantry.display_unit_type(UnitDefinition.UnitType.INFANTRY)
	check(infantry.get_node("MeshInstance3D").mesh is SphereMesh,"frozen historical infantry presentation")
	infantry.free()
	manager.free()
	print("06C SETUP: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
