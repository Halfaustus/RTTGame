extends SceneTree

var checks := 0
var failures := 0
var snapshot: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ConfirmedGameData.PATH))

func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("P1 FAIL: "+label)

func code(result: Dictionary,wanted: String,path: String = "") -> bool:
	for issue: Dictionary in result.errors:
		if issue.code == wanted and (path.is_empty() or issue.path == path): return true
	return false

func stock_check(unit: UnitState,label: String) -> void:
	check(unit.squad_channels.all_inventory_issues().is_empty(),label)

func spawn(config: UnitDefinition) -> UnitState:
	var result := UnitState.new(1,42,Vector3.ZERO)
	result.configure(1,config)
	return result

func run() -> void:
	var digest := FileAccess.get_sha256(ConfirmedGameData.PATH)
	var workbook := FileAccess.get_sha256("res://../docs/RTT_GAME_DATA.xlsx")
	var frozen := FileAccess.get_sha256("res://tests/fixtures/replay_v1.json")
	var data := ConfirmedGameData.new()
	check(data.validation_report.valid,"A13 current source and snapshot accepted")
	check(data.validation_report.source_verification == "actual_workbook_and_pinned_export","A13 actual workbook checked when available")
	check(data.validation_report.data_schema_version == 1 and data.validation_report.data_version != data.validation_report.rules_id,"A13 schema DATA revision and rules identities distinct")
	check(ConfirmedDataValidator.validate_snapshot(snapshot).valid,"A13 packaged server can validate pinned metadata without shipping workbook")
	var broken := snapshot.duplicate(true)
	broken.source_sha256 = "0".repeat(64)
	var result := ConfirmedDataValidator.validate_snapshot(broken)
	check(code(result,"source_hash_mismatch","source_sha256"),"A13 wrong claimed source hash located")
	check(code(ConfirmedDataValidator.validate_snapshot(snapshot,"0".repeat(64)),"actual_source_hash_mismatch"),"A13 wrong actual workbook hash refused")
	broken = snapshot.duplicate(true)
	broken.source = "other.xlsx"
	check(code(ConfirmedDataValidator.validate_snapshot(broken),"source_mismatch","source"),"A13 source identity checked")
	for field: String in ["data_schema_version","data_version","rules_id"]:
		broken = snapshot.duplicate(true)
		broken[field] = 999 if field == "data_schema_version" else "unknown"
		check(not ConfirmedDataValidator.validate_snapshot(broken).valid,"A13 unsupported "+field)
	broken = snapshot.duplicate(true)
	broken.baseline_id = "legacy-mismatch"
	check(code(ConfirmedDataValidator.validate_snapshot(broken),"legacy_rules_mismatch"),"A13 legacy alias cannot override rules identity")
	for sheet: String in ConfirmedDataValidator.ID_FIELDS:
		broken = snapshot.duplicate(true)
		broken.sheets.erase(sheet)
		check(code(ConfirmedDataValidator.validate_snapshot(broken),"missing_or_invalid_sheet","sheets."+sheet),"A13 required sheet "+sheet)
	for sheet: String in ["Weapons","Ammo"]:
		broken = snapshot.duplicate(true)
		broken.sheets[sheet].append(broken.sheets[sheet][0].duplicate(true))
		check(code(ConfirmedDataValidator.validate_snapshot(broken),"duplicate_id"),"A13 duplicate "+sheet+" ID refused")
	broken = snapshot.duplicate(true)
	broken.sheets.Ammo[0].erase("D0")
	check(code(ConfirmedDataValidator.validate_snapshot(broken),"missing_column","sheets.Ammo[0].D0"),"A13 missing column located")
	broken = snapshot.duplicate(true)
	broken.sheets.Ammo[0].Weapon_ID = "absent"
	check(code(ConfirmedDataValidator.validate_snapshot(broken),"missing_weapon_reference","sheets.Ammo[0].Weapon_ID"),"A13 dangling compatibility source reference")
	var rejected := ConfirmedGameData.new(broken)
	check(not rejected.validation_report.valid and rejected.records.is_empty() and rejected.weapon("W_MP7") == null,"A13 rejected export publishes no partial records")
	broken = snapshot.duplicate(true)
	broken.sheets.Weapons[0] = "not-a-row"
	check(code(ConfirmedDataValidator.validate_snapshot(broken),"invalid_row","sheets.Weapons[0]"),"A13 malformed row gives diagnostics rather than script error")
	broken = snapshot.duplicate(true)
	broken.sheets = []
	check(code(ConfirmedDataValidator.validate_snapshot(broken),"invalid_sheets"),"A13 malformed tables rejected")
	check(not ConfirmedDataValidator.validate_snapshot(null).valid,"A13 malformed JSON rejected")
	broken = snapshot.duplicate(true)
	broken.sheets.Weapons[0].Weapon_ID = ""
	check(code(ConfirmedDataValidator.validate_snapshot(broken),"invalid_id"),"A13 empty stable ID refused")
	broken = snapshot.duplicate(true)
	broken.sheets.Parameters = broken.sheets.Parameters.filter(func(row): return row.Parameter != "当前AT4班组配置数量上限")
	check(code(ConfirmedDataValidator.validate_snapshot(broken),"missing_parameter_reference"),"A13 required adapter parameter reference checked")
	broken = snapshot.duplicate(true)
	broken.sheets.Ammo[0].Initial_Inventory_rounds = -1
	check(code(ConfirmedDataValidator.validate_snapshot(broken),"invalid_inventory_value","sheets.Ammo[0].Initial_Inventory_rounds"),"A13 malformed stock type/value refused on load")
	broken.sheets.Ammo[0].Initial_Inventory_rounds = "unknown-marker"
	check(code(ConfirmedDataValidator.validate_snapshot(broken),"invalid_inventory_value"),"A13 unknown stock text is not a missing-value marker")
	# A01: mutate only the injected isolated snapshot, not the workbook/export.
	broken = snapshot.duplicate(true)
	for row: Dictionary in broken.sheets.Weapons:
		if row.Weapon_ID == "W_M4A1": row.Initial_Inventory_rounds = 999999
	var inventory_data := ConfirmedGameData.new(broken)
	result = inventory_data.initial_inventory_for_weapon("W_M4A1")
	check(result.valid and result.complete and result.source == "Ammo.Initial_Inventory_rounds" and result.inventory == {"A_556":150},"A01 dormant Weapons stock cannot add or override Ammo stock")
	var config := GeneratedCombatCatalog.squad()
	var unit := spawn(config)
	check(unit.squad_channels.channels.W_M4A1.inventory.A_556 == 450,"A01 active rifle stock equals only three allocations")
	check(unit.squad_channels.channels.W_M249.inventory.A_556_M249 == 750,"A01 active LMG stock enters once")
	for item: WeaponAllocation in config.weapon_allocations:
		check(item.initial_inventory == data.initial_inventory_for_weapon(item.definition.definition_id).inventory,"A01 active catalog uses shared stock adapter")
	var allocations_before := config.weapon_allocations[1].initial_inventory.duplicate(true)
	unit.squad_channels.channels.W_M4A1.consume("A_556",3)
	unit.squad_channels.channels.W_M4A1.pending_rounds -= 3
	check(config.weapon_allocations[1].initial_inventory == allocations_before,"A01 runtime mutation does not write initial allocation")
	stock_check(unit,"A09 initial commit follows source quotas")
	result = data.initial_inventory_for_weapon("W_AT4")
	check(not result.complete and result.inventory.is_empty() and result.missing[0].source_value == "未配置","A01 missing stock is explicit and not zero/default")
	var missing_data := ConfirmedGameData.new(snapshot)
	for row: Dictionary in missing_data.records.Ammo:
		if row.Ammo_ID == "A_AT4": row.Initial_Inventory_rounds = "不适用"
	result = missing_data.initial_inventory_for_weapon("W_AT4")
	check(result.missing[0].source_value == "不适用","A01 N/A stays distinct from missing")
	for row: Dictionary in missing_data.records.Ammo:
		if row.Ammo_ID == "A_AT4": row.Initial_Inventory_rounds = 0
	result = missing_data.initial_inventory_for_weapon("W_AT4")
	check(result.complete and result.inventory == {"A_AT4":0},"A01 real zero retained")
	for row: Dictionary in missing_data.records.Ammo:
		if row.Ammo_ID == "A_AT4": row.Initial_Inventory_rounds = -1
	check(code(missing_data.initial_inventory_for_weapon("W_AT4"),"invalid_initial_stock"),"A01 negative stock rejected")
	check(not data.initial_inventory_for_weapon("absent").valid,"A01 missing weapon diagnostic")
	check(code(data.initial_inventory_for_weapon("W_SHOTGUN"),"unconfigured_ammo_relation"),"A01 missing ammo association is not inferred as complete zero stock")
	# A02: one existing ammo record explicitly compatible with a second weapon.
	var relation_data := ConfirmedGameData.new(snapshot)
	var relations := relation_data.compatibility_relations()
	relations.append({"weapon_id":"W_MP7","ammo_id":"A_556"})
	check(relation_data.configure_compatibility(relations).valid,"A02 explicit reuse relation accepted")
	var reused := relation_data.weapon("W_MP7")
	check(reused.ammo_definitions.map(func(ammo): return ammo.ammo_id) == ["A_MP7","A_556"],"A02 relation order preserved and no source row copied")
	check(relation_data.records.Ammo.size() == snapshot.sheets.Ammo.size(),"A02 performance table not migrated or duplicated")
	check(reused.ammo_definitions[1].nominal_damage == relation_data.ammunition("A_556").nominal_damage and relation_data.weapon("W_M4A1").ammo_definitions[0].ammo_id == "A_556","A02 both weapons reference same Ammo identity/source performance")
	var extra := relation_data.initial_inventory_for_weapon("W_MP7")
	check(not extra.inventory.has("A_556") and extra.missing[0].reason == "explicit_configuration_required_for_reuse","A02 added compatibility does not automatically equip stock")
	var invalid_relations := relations.duplicate(true)
	invalid_relations.append(relations[0].duplicate(true))
	check(code(relation_data.configure_compatibility(invalid_relations),"duplicate_compatibility"),"A02 duplicate pair cannot duplicate stock")
	check(relation_data.compatible_ammo_ids("W_MP7") == ["A_MP7","A_556"],"A02 invalid relation replacement is transactional")
	invalid_relations = [{"weapon_id":"absent","ammo_id":"A_556"}]
	check(code(relation_data.configure_compatibility(invalid_relations),"missing_weapon_reference"),"A02 unknown weapon rejected")
	invalid_relations = [{"weapon_id":"W_MP7","ammo_id":"absent"}]
	check(code(relation_data.configure_compatibility(invalid_relations),"missing_ammo_reference"),"A02 unknown ammo rejected")
	invalid_relations = [{"weapon_id":"W_MP7","ammo_id":"A_556","initial_inventory":20}]
	check(code(relation_data.configure_compatibility(invalid_relations),"unexpected_relation_field"),"A02 relation cannot store a stock/performance override")
	var first_stock: Dictionary = relation_data.initial_inventory_for_weapon("W_MP7").inventory
	first_stock.A_MP7 = 0
	check(relation_data.initial_inventory_for_weapon("W_MP7").inventory.A_MP7 == 150,"A02 independent configuration inventory not stored on relation")
	check(data.compatible_ammo_ids("W_MP7") == ["A_MP7"],"A02 explicit relations cannot affect another DATA adapter")
	# A09: fixed channel, stable source order, cross-source debit.
	config = GeneratedCombatCatalog.squad()
	config.weapon_allocations[1].initial_inventory = {"A_556":1}
	config.weapon_allocations[2].initial_inventory = {"A_556":4}
	config.weapon_allocations[3].initial_inventory = {"A_556":5}
	unit = spawn(config)
	var channel: RuntimeWeaponInstance = unit.squad_channels.channels.W_M4A1
	stock_check(unit,"A09 initialization reconciles each ammo")
	var identity := channel.instance_id
	channel.consume("A_556",3)
	channel.pending_rounds -= 3
	stock_check(unit,"A09 cross-source debit reconciles")
	check(channel.inventory.A_556 == 7 and unit.squad_channels.source_groups[identity][0].inventory.A_556 == 0 and unit.squad_channels.source_groups[identity][1].inventory.A_556 == 2,"A09 source debit order unchanged")
	unit.members[1].health = 0
	stock_check(unit,"A09 death removes spent source zero quota only")
	check(channel.inventory.A_556 == 7,"A09 dead exhausted source removes no live quota")
	unit.members[2].health = 0
	stock_check(unit,"A09 death removes partially consumed remaining quota")
	check(channel.inventory.A_556 == 5,"A09 removal uses remaining two not initial four")
	unit.members[2].health = 5
	stock_check(unit,"A09 revival/reassignment reconciles without refill")
	check(channel.inventory.A_556 == 5 and channel.instance_id == identity and channel.configured_count == 3,"A09 no inventory or fixed N regeneration")
	channel.consume("A_556",5)
	channel.pending_rounds -= 5
	stock_check(unit,"A09 depleted channel and ready counter reconcile")
	check(channel.inventory.A_556 == 0 and channel.pending_rounds == 0,"A09 empty stock is real zero")
	config = GeneratedCombatCatalog.squad()
	unit = spawn(config)
	var lmg: RuntimeWeaponInstance = unit.squad_channels.channels.W_M249
	lmg.consume("A_556_M249",3)
	lmg.pending_rounds -= 3
	unit.members[0].health = 0
	stock_check(unit,"A09 squad weapon reassignment preserves accounting")
	check(lmg.node_id == "2" and lmg.inventory.A_556_M249 == 0,"A09 transfer never restores lost carrier stock")
	unit.members[0].health = 5
	stock_check(unit,"A09 original role restored without refill")
	channel = unit.squad_channels.channels.W_M4A1
	channel.inventory.A_556 += 1
	result = {"errors":unit.squad_channels.inventory_issues(channel)}
	check(code(result,"inventory_ledger_mismatch"),"A09 deliberate ledger corruption identified")
	channel.inventory.A_556 -= 1
	var stock: int = channel.inventory.A_556
	channel.pending_rounds = channel.pending_capacity()+1
	result = {"errors":unit.squad_channels.inventory_issues(channel)}
	check(code(result,"pending_outside_stock"),"A09 ready count never added to total inventory")
	channel.pending_rounds = mini(channel.pending_capacity(),stock)
	stock_check(unit,"A09 restored diagnostic test state reconciles")
	# Same total is insufficient: reconcile EACH ammo, including loading/death.
	config = UnitDefinition.new()
	config.configuration_source = "test_only:p1_multi_ammo"
	config.member_count = 4
	var cg := data.weapon("W_CG")
	for i: int in 2:
		var allocation := WeaponAllocation.new()
		allocation.definition = cg
		allocation.member_id = i+1
		allocation.retention_priority = 0
		allocation.initial_inventory = {"A_CG_HEAT":1+i,"A_CG_HE":2-i}
		config.weapon_allocations.append(allocation)
	unit = spawn(config)
	channel = unit.squad_channels.channels.W_CG
	stock_check(unit,"A09 multi-ammo initialization reconciles individually")
	var previous_stock := channel.inventory.duplicate()
	channel.consume("A_CG_HEAT",1)
	channel.pending_rounds -= 1
	stock_check(unit,"A09 first multi-ammo shot reconciles")
	channel.initialize_first_magazine()
	stock_check(unit,"A09 reload only restores readiness within total stock")
	check(channel.inventory.A_CG_HEAT == previous_stock.A_CG_HEAT-1 and channel.inventory.A_CG_HE == previous_stock.A_CG_HE,"A09 reload does not create or transfer ammo")
	channel.consume("A_CG_HE",1)
	channel.pending_rounds -= 1
	stock_check(unit,"A09 selected second ammo debits its own quotas")
	unit.members[0].health = 0
	stock_check(unit,"A09 multi-ammo source death removes remaining quotas")
	unit.members[0].health = 5
	stock_check(unit,"A09 multi-ammo revival adds no stock")
	channel.inventory.A_CG_HEAT += 1
	channel.inventory.A_CG_HE -= 1
	check(code({"errors":unit.squad_channels.inventory_issues(channel)},"inventory_ledger_mismatch"),"A09 equal grand total with wrong ammo distribution fails")
	channel.inventory.A_CG_HEAT -= 1
	channel.inventory.A_CG_HE += 1
	stock_check(unit,"A09 restored per-ammo distribution reconciles")
	# Real firing/pool path: loaded and in-flight never create a second debit.
	unit = spawn(GeneratedCombatCatalog.squad())
	var aiming := AimingSimulation.new()
	aiming.units = {1:unit}
	aiming.visibility = func(_a,_b): return true
	aiming.clear_path = func(_a,_b): return true
	aiming.moving = func(_id): return false
	for item: RuntimeWeaponInstance in unit.runtime_weapons: item.bind_target(AttackTarget.ground(Vector3(0,0,-30)))
	aiming.advance(1)
	var timeline := DB29CombatTimeline.new()
	timeline.fire.fire_path_permission = func(_w,_a,_b,_i): return true
	var emissions: Array = timeline.step(aiming).emissions
	check(emissions.size() == 2,"A09 actual fixed scheduler emits two model channels")
	stock_check(unit,"A09 after complete emission/pending update accounting stable")
	var remaining: Dictionary = unit.squad_channels.channels.W_M4A1.inventory.duplicate()
	timeline.projectiles.step()
	stock_check(unit,"A09 in-flight update does not alter quota")
	check(unit.squad_channels.channels.W_M4A1.inventory == remaining,"A09 projectile consumer does not double-debit")
	timeline.projectiles.collision.close()
	check(FileAccess.get_sha256(ConfirmedGameData.PATH) == digest and FileAccess.get_sha256("res://../docs/RTT_GAME_DATA.xlsx") == workbook and FileAccess.get_sha256("res://tests/fixtures/replay_v1.json") == frozen,"P1 isolated tests do not overwrite protected data")
	print("P1 schema contracts: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
