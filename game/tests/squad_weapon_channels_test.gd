extends SceneTree

var checks := 0
var failures := 0
var data := ConfirmedGameData.new()
var next_id := 1000

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL channels: "+label)

func test_weapon(id: String) -> WeaponDefinition:
	var value := data.weapon(id)
	# ONLY isolated missing-field fills. Confirmed performance remains untouched.
	if value.required_operators < 0: value.required_operators = 1
	if not is_finite(value.aim_min_seconds):
		value.aim_min_seconds = 0.1
		value.aim_max_seconds = 0.1
	value.allowed_target_types = [WeaponDefinition.TargetType.INFANTRY,WeaponDefinition.TargetType.GROUND_VEHICLE]
	value.reduction_ignore = 0
	value.temporary_fields.assign(["test_only:operators_if_missing","test_only:aim_if_missing","test_only:allowed_target_types","test_only:reduction_ignore"])
	return value

func allocation(unit: UnitDefinition, weapon: WeaponDefinition, member: int, priority: int, slot: String = "primary") -> void:
	var value := WeaponAllocation.new()
	value.definition = weapon
	value.member_id = member
	value.slot_id = slot
	value.retention_priority = priority
	for ammo: AmmoDefinition in weapon.ammo_definitions:
		var count := data.number(data.record("Ammo",ammo.ammo_id),"Initial_Inventory_rounds")
		if is_finite(count): value.initial_inventory[ammo.ammo_id] = int(count)
	unit.weapon_allocations.append(value)

func definition(count: int) -> UnitDefinition:
	var value := UnitDefinition.new()
	value.configuration_source = "test_only:db29_channel_fixture"
	value.resource_name = "test_only_db29_channel_fixture"
	value.member_count = count
	value.protection_kinetic = 6
	value.protection_chemical = 6
	return value

func state(config: UnitDefinition) -> UnitState:
	next_id += 1
	var unit := UnitState.new(next_id,42,Vector3.ZERO)
	unit.configure(1,config)
	return unit

func channel(unit: UnitState, model: String) -> RuntimeWeaponInstance:
	return unit.squad_channels.channels.get(model)

func aiming(unit: UnitState) -> AimingSimulation:
	var result := AimingSimulation.new()
	var enemy := state(definition(1))
	enemy.team_id = 2
	enemy.position = Vector3(0,0,-10)
	result.units = {unit.unit_id:unit,enemy.unit_id:enemy}
	result.visibility = func(_a,_b): return true
	result.clear_path = func(_a,_b): return true
	result.moving = func(_id): return false
	for weapon: RuntimeWeaponInstance in unit.runtime_weapons: weapon.bind_target(AttackTarget.unit(enemy))
	result.advance(3)
	return result

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var digest := FileAccess.get_sha256(ConfirmedGameData.PATH)
	var rifle := test_weapon("W_M4A1")
	for count: int in [1,3,7]:
		var config := definition(count)
		for id: int in range(1,count+1): allocation(config,rifle,id,1)
		var unit := state(config)
		var weapon := channel(unit,"W_M4A1")
		check(unit.runtime_weapons.size() == 1 and unit.runtime_slots.size() == count,"one timer, physical slots N="+str(count))
		check(weapon.configured_count == count and weapon.operable_count == count,"explicit configured count N="+str(count))
		check(is_equal_approx(weapon.shot_interval(),data.weapon("W_M4A1").game_projectile_interval/count),"N applied once "+str(count))
		check(unit.runtime_slots.all(func(s): return s.runtime_weapon == weapon),"all slots point to same authority")
		var aim := aiming(unit)
		check(weapon.is_aimed,"real 05D aim N="+str(count))
		var fire := FireSimulation.new()
		var first := fire.advance(0,1,aim)
		check(first.size() == 1 and first[0].consumed == 3,"one projectile, three rounds")
		check(weapon.inventory.A_556 == 150*count-3 and weapon.pending_rounds == 27,"atomic aggregate inventory and channel pending")
		var interval := weapon.shot_interval()
		check(fire.advance(interval-0.001,2,aim).is_empty(),"no early emission")
		check(fire.advance(0.001,3,aim).size() == 1,"formal cadence endpoint")
		check(unit.runtime_weapons[0] == weapon,"runtime not rebuilt during updates")
		if count == 3:
			var stable := weapon.instance_id
			var flow := weapon.fire_state
			var progress := weapon.aim_progress
			unit.members[0].health = 0
			unit.refresh_weapon_operators()
			check(weapon.configured_count == 3 and weapon.operable_count == 2,"casualty doesn't change N")
			check(weapon.inventory.A_556 == 300,"dead carrier remaining ammo removed exactly")
			check(weapon.instance_id == stable and weapon.fire_state == flow and weapon.aim_progress == progress,"identity timers and progress survive representative change")
			check(is_equal_approx(weapon.shot_interval(),2.4),"casualty doesn't renormalize cadence")
			config.weapon_allocations.reverse()
			var reordered := state(config)
			check(channel(reordered,"W_M4A1").instance_id.get_slice("/squad/",1) == stable.get_slice("/squad/",1),"stable identity independent of allocation order")
	var mixed := definition(4)
	var lmg := test_weapon("W_M249")
	allocation(mixed,lmg,1,0)
	allocation(mixed,rifle,2,1)
	allocation(mixed,rifle,3,1)
	allocation(mixed,rifle,4,1)
	var squad := state(mixed)
	var machine := channel(squad,"W_M249")
	var rifles := channel(squad,"W_M4A1")
	check(squad.runtime_weapons.size() == 2 and machine.fire_state != rifles.fire_state,"different models have independent timers")
	check(is_equal_approx(machine.shot_interval(),2.4) and is_equal_approx(rifles.shot_interval(),2.4),"independent formal intervals")
	var aim := aiming(squad)
	var fire := FireSimulation.new()
	check(fire.advance(0,1,aim).size() == 2,"different model channels fire in parallel")
	var flow := machine.fire_state
	squad.members[0].health = 0
	squad.refresh_weapon_operators()
	check(machine.node_id == "2" and machine.operable_count == 1,"squad weapon transferred to survivor")
	check(rifles.operable_count == 2 and rifles.configured_count == 3,"recipient primary stops without rewriting N")
	check(machine.inventory.A_556_M249 == 0 and machine.fire_state == flow,"dead carrier ammo removed, no extra ammo on transfer")
	squad.members[0].health = 5
	squad.refresh_weapon_operators()
	check(machine.node_id == "1" and rifles.operable_count == 3 and machine.inventory.A_556_M249 == 0,"replenishment restores allocations without full refill")
	var heavy := definition(2)
	var m2 := test_weapon("W_M2")
	allocation(heavy,m2,1,0)
	var crew := state(heavy)
	var heavy_channel := channel(crew,"W_M2")
	check(heavy_channel.definition.required_operators == 2 and heavy_channel.operable_count == 1,"formal M2 two operators")
	var crew_aim := aiming(crew)
	check(crew_aim.eligibility(heavy_channel) == "eligible","enough operators")
	crew.members[1].health = 0
	crew.refresh_weapon_operators()
	check(crew_aim.eligibility(heavy_channel) == "operators_insufficient" and heavy_channel.configured_count == 1,"below minimum explicitly blocks fire without changing N")
	check(FireSimulation.new().advance(0,1,crew_aim).is_empty(),"insufficient operators cannot debit ammo")
	heavy_channel.fire_state.loading = true
	heavy_channel.fire_state.loading_progress = 0.25
	FireSimulation.new().advance(1,1,crew_aim)
	check(heavy_channel.fire_state.loading_progress == 0.25,"no operators cannot operate preparation; fraction preserved")
	var missing := definition(1)
	allocation(missing,data.weapon("W_M4A1"),1,1)
	var incomplete := state(missing)
	check(channel(incomplete,"W_M4A1").operator_reason == "operator_configuration_missing","missing formal minimum never legacy one")
	check(data.squad_configuration("INF6").reason == "squad_configuration_missing" and data.squad_configuration("INF6").missing_fields.has("weapon_allocations"),"formal N absent, no six/two fallback")
	var absent_priority := definition(1)
	allocation(absent_priority,lmg,1,-1)
	check(channel(state(absent_priority),"W_M249").operator_reason == "operator_configuration_missing","missing retention priority rejected")
	var conflict := definition(2)
	allocation(conflict,data.weapon("W_M4A1"),1,1)
	allocation(conflict,data.weapon("W_M4A1"),2,1)
	check(not conflict.weapon_allocations_valid(),"same model conflicting definition resources reject")
	var at4 := data.weapon("W_AT4")
	check(at4.capacity == -1 and is_nan(at4.preparation_seconds) and is_nan(at4.game_projectile_interval),"AT4 remains missing")
	check(at4.maximum_squad_count == 5,"AT4 count limit from DATA, not inventory")
	var excessive := definition(6)
	for id: int in range(1,7): allocation(excessive,at4,id,1,"secondary")
	check(not excessive.weapon_allocations_valid(),"AT4 configured quantity above DATA limit rejected")
	var secondary := definition(1)
	allocation(secondary,rifle,1,1)
	var rocket_test := at4.duplicate()
	rocket_test.required_operators = 1
	allocation(secondary,rocket_test,1,1,"secondary")
	var both := state(secondary)
	check(channel(both,"W_M4A1").operable_count == 1 and channel(both,"W_AT4").operable_count == 1,"legal ordinary secondary doesn't steal primary operator")
	var cg_config := definition(2)
	var cg := test_weapon("W_CG")
	allocation(cg_config,cg,1,0)
	allocation(cg_config,cg,2,0)
	var cg_unit := state(cg_config)
	var cg_channel := channel(cg_unit,"W_CG")
	var cg_aim := aiming(cg_unit)
	var cg_fire := FireSimulation.new()
	check(cg_fire.advance(0,1,cg_aim).size() == 1 and cg_channel.fire_state.loading,"CG prepares after every round")
	check(is_equal_approx(cg_channel.loading_seconds(),3),"CG DATA six seconds divided by explicit two once")
	check(cg_fire.advance(2.999,2,cg_aim).is_empty() and cg_fire.advance(0.001,3,cg_aim).size() == 1,"CG preparation cadence endpoint")
	var active := Prototype05DCatalog.shared()
	for pair: Array in [["rifle","W_M4A1"],["lmg","W_M249"],["vehicle_mg","W_M249V"]]:
		check(active.weapons[pair[0]].data_source == "DB29:RTT_GAME_DATA.xlsx" and active.weapons[pair[0]].game_projectile_interval == data.weapon(pair[1]).game_projectile_interval,"active formal performance "+str(pair[0]))
	var preset := active.squad(false)
	check(preset.configuration_source.begins_with("test_only:") and preset.resource_name.begins_with("test_only_"),"activity layout explicitly test only")
	check(state(preset).unassigned_inventory.is_empty(),"active AT4 doesn't inherit five stock")
	check(data.weapon("W_M4A1").required_operators == -1 and data.weapon("W_M4A1").allowed_target_types.is_empty(),"test fills don't mutate formal data")
	check(active.ammunition.has("A_556") and not active.ammunition.has("standard"),"activity ammunition catalog excludes legacy aliases")
	check(is_equal_approx(data.weapon("W_M4A1").actual_round_interval*3,data.weapon("W_M4A1").game_projectile_interval),"DATA rpm and abstract projectile cadence consistent")
	var invalid_state := state(excessive)
	check(invalid_state.armament_configuration_reason == "invalid_weapon_allocations" and invalid_state.runtime_weapons.is_empty(),"invalid source explicitly rejected before construction")
	# Existing 05F payload contract consumed without another inventory debit.
	var ballistic := rifle.duplicate()
	ballistic.projectile = ProjectileDefinition.new()
	ballistic.projectile.speed_mps = 900 # DATA A_556 3240km/h, no temporary override.
	ballistic.projectile.radius_m = 0.025 # Existing 05F TEST ONLY collision configuration.
	ballistic.projectile.lifetime_seconds = 8 # Existing 05F TEST ONLY lifecycle.
	ballistic.projectile.spread_radius_m = 0.15 # Existing 05F TEST ONLY spread.
	var ballistic_config := definition(2)
	allocation(ballistic_config,ballistic,1,1)
	allocation(ballistic_config,ballistic,2,1)
	var ballistic_unit := state(ballistic_config)
	var ballistic_aim := aiming(ballistic_unit)
	var shots := FireSimulation.new().advance(0,1,ballistic_aim)
	check(shots.size() == 1 and shots[0].weapon_instance_id == channel(ballistic_unit,"W_M4A1").instance_id and shots[0].ammo_definition_id == "A_556","new channel emits existing 05F payload")
	var stock := channel(ballistic_unit,"W_M4A1").inventory.duplicate()
	var flight := ProjectileSimulation.new()
	flight.consume(shots)
	check(flight.active.size() == 1 and channel(ballistic_unit,"W_M4A1").inventory == stock,"05F consumes exactly once without duplicate ammo debit")
	flight.consume(shots)
	check(flight.active.size() == 1,"05F event deduplication unchanged")
	flight.active.clear()
	var missing_source := definition(1)
	allocation(missing_source,rifle,1,1)
	missing_source.configuration_source = "unconfigured"
	check(channel(state(missing_source),"W_M4A1").operator_reason == "source_configuration_missing","unconfigured source refused")
	check(FileAccess.get_sha256(ConfirmedGameData.PATH) == digest,"fixtures don't write DATA")
	print("DB29 channels: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
