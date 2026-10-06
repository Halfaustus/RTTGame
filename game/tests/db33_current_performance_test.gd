extends "res://tests/db29_combat_timeline_test.gd"

# Current acceptance on generated TEST ONLY units, never INF/vehicle DATA units.
# Weapon performance and ammunition identity come directly from current DATA.
func mounted_fixture(model: String) -> Dictionary:
	var test := fixture(1)
	var config := UnitDefinition.new()
	config.resource_name = "test_only_db33_mount"
	config.configuration_source = "test_only:db33_mount"
	config.unit_type = UnitDefinition.UnitType.ARMORED_VEHICLE
	config.maximum_health = 10
	var mount := WeaponMountDefinition.new()
	mount.mount_id = "test.main"
	mount.rotation_speed_degrees = 120
	config.mounts.append(mount)
	var weapon := data.weapon(model)
	if weapon.required_operators < 0: weapon.required_operators = 1
	if not is_finite(weapon.aim_min_seconds):
		weapon.aim_min_seconds = 0.1
		weapon.aim_max_seconds = 0.1
	weapon.allowed_target_types = [WeaponDefinition.TargetType.INFANTRY]
	if weapon.moving_aim_qualification < 0: weapon.moving_aim_qualification = 0
	weapon.reduction_ignore = 0
	weapon.spread_radius_m = 0 # Local exact-path prerequisite, not formal spread.
	weapon.temporary_fields.assign(["test_only:operators_if_missing","test_only:aim_if_missing","test_only:moving_eligibility_if_missing","test_only:target_types","test_only:ignore","test_only:spread"])
	var allocation := WeaponAllocation.new()
	allocation.definition = weapon
	allocation.node_kind = WeaponAllocation.NodeKind.MOUNT
	allocation.mount_id = mount.mount_id
	allocation.retention_priority = 0
	for ammo: AmmoDefinition in weapon.ammo_definitions:
		allocation.initial_inventory[ammo.ammo_id] = int(data.number(data.record("Ammo",ammo.ammo_id),"Initial_Inventory_rounds"))
	config.weapon_allocations.append(allocation)
	test.unit.configure(1,config)
	test.weapon = test.unit.runtime_weapons[0]
	test.weapon.bind_target(AttackTarget.unit(test.target))
	test.aiming.advance(3)
	return test

func run() -> void:
	var digest := FileAccess.get_sha256(ConfirmedGameData.PATH)
	for id: String in ["W_M4A1","W_M249","W_M249V","W_M242","W_MK44"]:
		var test := fixture(1,id) if id in ["W_M4A1","W_M249"] else mounted_fixture(id)
		var runtime: RuntimeWeaponInstance = test.weapon
		var row := data.record("Weapons",id)
		var expected_interval := data.number(row,"Single_Weapon_Projectile_Interval_s")
		check(runtime.definition.definition_id == id and runtime.definition.data_source == "DB29:RTT_GAME_DATA.xlsx",id+" actual runtime references DATA weapon")
		check(is_equal_approx(runtime.shot_interval(),expected_interval),id+" interval sourced from DATA exactly once")
		check(runtime.definition.capacity == int(row.Capacity_rounds),id+" capacity sourced from DATA")
		check(runtime.definition.preparation_seconds == data.number(row,"Reload_s"),id+" reload sourced from DATA")
		var baseline: Dictionary = runtime.inventory.duplicate()
		var timeline: DB29CombatTimeline = test.timeline
		var first := timeline.step(test.aiming)
		check(first.emissions.size() == 1,id+" legal prepared runtime emits: "+runtime.fire_state.reason)
		if first.emissions.is_empty(): continue
		var emission: Dictionary = first.emissions[0]
		var ammo: AmmoDefinition = emission.ammo
		check(data.record("Ammo",ammo.ammo_id).Weapon_ID == id,id+" actual selected ammo belongs to corresponding weapon")
		check(is_equal_approx(emission.velocity.length(),data.number(data.record("Ammo",ammo.ammo_id),"Projectile_Speed_kmh")/3.6),id+" actual initial speed from selected DATA ammo")
		check(runtime.inventory[ammo.ammo_id] == baseline[ammo.ammo_id]-runtime.definition.consumption_per_projectile,id+" actual atomic debit uses formal aggregation")
		var second: Dictionary = {}
		for step_index: int in ceili(expected_interval/GravityBallistics.STEP_SECONDS)+1:
			var result := timeline.step(test.aiming)
			if not result.emissions.is_empty():
				second = result.emissions[0]
				break
		check(not second.is_empty() and absf(float(second.get("time_seconds",-1))-expected_interval) < 0.000001,id+" second emission at DATA interval, not old 1/1.5s")
	var rifle := data.ammunition("A_556")
	var lmg := data.ammunition("A_556_M249")
	check(rifle.ammo_id != lmg.ammo_id and rifle != lmg,"rifle and LMG keep explicit distinct ammo relationships")
	check(AmmoSelection.penetration(rifle,0) == 9 and absf(AmmoSelection.penetration(rifle,500)-6) < 0.000001,"DATA replaces old P12/400m5 acceptance")
	check(data.weapon("W_MP7").range_m == 150 and data.ammunition("A_MP7").nominal_damage == 0.6,"MP7 uses DATA, not legacy PDW200m/0.8")
	var rocket := data.weapon("W_AT4")
	check(rocket.maximum_squad_count == 5 and rocket.capacity == -1 and is_nan(rocket.preparation_seconds),"AT4 limit is not capacity or preparation")
	var activity := Prototype05DCatalog.shared().squad(false)
	check(activity.configuration_source.begins_with("test_only:") and activity.resource_name.begins_with("test_only"),"active generated layout is explicitly TEST ONLY")
	var unit := UnitState.new(9500,42,Vector3.ZERO)
	unit.configure(1,activity)
	check(unit.unassigned_inventory.is_empty(),"current activity never fills AT4 stock from old five-item fixture")
	check(not unit.runtime_weapons.any(func(weapon): return weapon.definition.definition_id == "W_AT4"),"unconfigured AT4 does not acquire a runtime launcher")
	check(FileAccess.get_sha256(ConfirmedGameData.PATH) == digest,"generated tests never write formal DATA")
	print("DB33 current performance: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
