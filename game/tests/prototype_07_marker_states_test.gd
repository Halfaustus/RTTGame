extends "res://tests/prototype_06e_integration_test.gd"

func run() -> void:
	var formal := FileAccess.get_sha256(ConfirmedGameData.PATH)
	var frozen := FileAccess.get_sha256("res://tests/fixtures/replay_v1.json")
	var test := vehicle_fixture()
	var unit: UnitState = test.unit
	var weapon: RuntimeWeaponInstance = test.weapon
	weapon.definition.caliber_mm = 30 # TEST ONLY caliber, no formal instance configuration.
	weapon.sampled_aim_seconds = 2
	weapon.aim_progress = 0.25
	weapon.can_attack = true
	weapon.fire_state.loading = true
	weapon.fire_state.loading_progress = 0.25
	var status := UnitMarkerStatus.build(unit,test.aiming)
	var duration := weapon.loading_seconds()
	check(is_equal_approx(status.fire_progress.remaining_seconds,maxf(1.5,0.75*duration)),"single primary uses later of actual aim/load completion")
	test.aiming.inputs[unit.unit_id] = {"aim_time_multiplier":2.0,"loading_module_multiplier":2.0,"personnel_load_multiplier":3.0}
	status = UnitMarkerStatus.build(unit,test.aiming)
	check(is_equal_approx(status.fire_progress.remaining_seconds,0.75*duration*6),"personnel/module modifiers preserve remaining progress")
	weapon.definition.mechanical_loading = true
	status = UnitMarkerStatus.build(unit,test.aiming)
	check(is_equal_approx(status.fire_progress.remaining_seconds,maxf(3.0,0.75*duration*2)),"mechanical reload omits personnel modifier")
	weapon.definition.mechanical_loading = false
	test.aiming.inputs.clear()
	var secondary_allocation := unit.definition.weapon_allocations[0].duplicate(true) as WeaponAllocation
	secondary_allocation.slot_id = "test_only:secondary"
	secondary_allocation.definition.caliber_mm = 7.62
	unit.definition.weapon_allocations.append(secondary_allocation)
	unit.configure(1,unit.definition)
	weapon = unit.runtime_weapons[0]
	var secondary: RuntimeWeaponInstance = unit.runtime_weapons[1]
	for w: RuntimeWeaponInstance in unit.runtime_weapons:
		w.bind_target(AttackTarget.unit(test.target))
		w.can_attack = true
		w.sampled_aim_seconds = 2
		w.aim_progress = 0.0 if w == weapon else 0.9
	check(UnitMarkerStatus.primary_weapons(unit) == [weapon] and UnitMarkerStatus.next_fire(unit,test.aiming).remaining_seconds == 2,"largest caliber is default primary rather than earliest secondary")
	secondary.slot_state().definition.armored_primary_weapon = true
	check(UnitMarkerStatus.primary_weapons(unit) == [secondary] and is_equal_approx(UnitMarkerStatus.next_fire(unit,test.aiming).remaining_seconds,0.2),"explicit smaller-caliber primary overrides fallback")
	weapon.slot_state().definition.armored_primary_weapon = true
	check(is_equal_approx(UnitMarkerStatus.next_fire(unit,test.aiming).remaining_seconds,0.2),"multiple explicit primaries show earliest ready weapon")
	secondary.aim_progress = 1.0
	check(UnitMarkerStatus.next_fire(unit,test.aiming).is_empty(),"one ready primary hides the bar despite another primary waiting")
	for w: RuntimeWeaponInstance in unit.runtime_weapons: w.slot_state().definition.armored_primary_weapon = false
	secondary.definition.caliber_mm = 30
	secondary.aim_progress = 0.9
	check(UnitMarkerStatus.primary_weapons(unit).size() == 2 and is_equal_approx(UnitMarkerStatus.next_fire(unit,test.aiming).remaining_seconds,0.2),"equal largest calibers are multiple default primaries")
	secondary.definition.caliber_mm = NAN
	check(UnitMarkerStatus.primary_weapons(unit).is_empty() and UnitMarkerStatus.next_fire(unit,test.aiming).is_empty(),"unknown caliber never invents primary from names or known smaller weapon")
	weapon.slot_state().definition.armored_primary_weapon = true
	check(UnitMarkerStatus.primary_weapons(unit) == [weapon],"explicit primary works with unconfigured secondary caliber")
	weapon.can_attack = false
	check(UnitMarkerStatus.next_fire(unit,test.aiming).is_empty(),"no effective fire task hides progress")
	for w: RuntimeWeaponInstance in unit.runtime_weapons: w.enabled = false
	test.aiming.advance(0.1)
	status = UnitMarkerStatus.build(unit,test.aiming)
	check(status.hold_fire and status.engaged and status.laser == "inactive","disabled target task keeps hold-fire and engaged visible together after authoritative aiming")
	for w: RuntimeWeaponInstance in unit.runtime_weapons: w.clear_target()
	check(not UnitMarkerStatus.build(unit,test.aiming).engaged,"clearing all target tasks clears engaged")
	for w: RuntimeWeaponInstance in unit.runtime_weapons: w.bind_target(AttackTarget.unit(test.target))
	test.target.health = 0
	check(not UnitMarkerStatus.build(unit,test.aiming).engaged,"dead target never appears engaged")
	test.target.health = test.target.definition.maximum_health
	test.aiming.units.erase(test.target.unit_id)
	check(not UnitMarkerStatus.build(unit,test.aiming).engaged,"unregistered target never appears engaged")
	test.aiming.units[test.target.unit_id] = test.target
	status = UnitMarkerStatus.build(unit,test.aiming,{"laser":"paused","return_fire_only":true,"carried_personnel":8,"mixed_cargo":true})
	check(status.hold_fire and status.laser == "paused" and status.return_fire_only,"independent authoritative work/behavior state adapter")
	check(UnitMarkerStatus.valid_activity({"laser":"active","carried_personnel":5}) and not UnitMarkerStatus.valid_activity({"carried_personnel":-1}) and not UnitMarkerStatus.valid_activity({"inventory":1}),"activity rejects invalid count and arbitrary private data")
	unit.vehicle_modules = VehicleModuleState.new()
	var structure := unit.structure_snapshot()
	structure.marker_status = status
	var own := UnitStatusProjection.project(structure,true)
	var ally := UnitStatusProjection.project(structure,false)
	check(own.return_fire_only and own.laser == "paused" and own.hold_fire,"own marker includes permitted private work state")
	check(not ally.has("return_fire_only") and not ally.has("laser"),"return-fire and laser details absent from other players")
	check(ally.mixed_cargo and ally.carried_personnel == 0,"mixed cargo projects icon without passenger count")
	for key: String in ["weapons","members","Q","inventory","armored_primary_weapon","weapon_instance_id"]:
		check(not own.has(key) and not ally.has(key),"marker projection excludes "+key)
	var marker := UnitMarker.new()
	marker.unit_kind = UnitDefinition.UnitType.ARMORED_VEHICLE
	root.add_child(marker)
	marker.apply_status(own)
	check(marker.hold_fire and marker.laser_state == "paused" and marker.return_fire_only and marker.mixed_cargo,"production marker consumes work/behavior/cargo states")
	marker.apply_status(ally)
	check(not marker.return_fire_only and marker.laser_state == "inactive","switching recipient clears private states rather than retaining them")
	marker.apply_status({"personnel_state":"calm"})
	check(not marker.hold_fire and not marker.engaged and not marker.mixed_cargo and marker.fire_progress.is_empty(),"inactive snapshot clears all former indicators")
	marker.queue_free()
	var infantry := fixture(1)
	check(UnitMarkerStatus.next_fire(infantry.unit,infantry.aiming).is_empty(),"infantry without a configured primary or effective fire task hides progress")
	infantry.timeline.projectiles.collision.close()
	var model = load("res://scripts/networking/network_manager.gd").new()
	root.add_child(model)
	model._authoritative_units[unit.unit_id] = unit
	unit.owner_player_id = 10
	model._peer_players[42] = 10
	model._peer_players[43] = 11
	structure.marker_status = status
	var args: Array = model._replication_arguments_for_peer("_receive_unit_statuses",[[structure]],42)
	check(args.size() == 1 and args[0][0].return_fire_only,"actual peer projection carries own behavior")
	args = model._replication_arguments_for_peer("_receive_unit_statuses",[[structure]],43)
	check(args.size() == 1 and not args[0][0].has("return_fire_only") and not args[0][0].has("laser"),"actual peer projection protects private marker states")
	unit.team_id = 2
	check(model._replication_arguments_for_peer("_receive_unit_statuses",[[structure]],42).is_empty(),"undisclosed enemy states are withheld")
	check(not model.set_authoritative_marker_activity(-1,{"laser":"active"}) and model.set_authoritative_marker_activity(unit.unit_id,{"laser":"paused"}),"server activity API validates live unit")
	model.queue_free()
	test.timeline.projectiles.collision.close()
	check(FileAccess.get_sha256(ConfirmedGameData.PATH) == formal and FileAccess.get_sha256("res://tests/fixtures/replay_v1.json") == frozen,"DATA/frozen v1 remain unchanged")
	print("0.7 marker states checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
