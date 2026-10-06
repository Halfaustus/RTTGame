class_name Prototype05DCatalog
extends RefCounted

# Explicit prototype configuration; unknown formal fields remain marked temporary.
const TEST_AIM_SECONDS := 1.0
const TEST_A_RANGE_M := 1000.0
const AIM_TOLERANCE_DEGREES := 1.0
const RANGE_EPSILON_M := 0.00001
const RANDOM_SEED := 50504
const TEST_GUN_LOG_SHAPE := 1.0
var ammunition: Dictionary = {}
var weapons: Dictionary = {}
var default_inventory: Dictionary = {"pdw":{"pdw":150},"rifle":{"standard":150},"lmg":{"standard":750},"vehicle_mg":{"standard":2250},"shotgun":{"shotgun":50}}
static var _shared: Prototype05DCatalog

static func shared() -> Prototype05DCatalog:
	if _shared == null:
		_shared = Prototype05DCatalog.new()
		_shared.use_confirmed_performance()
	return _shared

func _init() -> void:
	_ammo("pdw", "kinetic",0.8,8,200,5)
	_ammo("standard", "kinetic",1.0,12,400,5)
	_ammo("recoilless_ap", "chemical",8,400,-1,400,100)
	_ammo("recoilless_he", "chemical",2,5,-1,5,0,3,100)
	_ammo("rocket_ap", "chemical",4,600,-1,600,100)
	_ammo("cannon_a_ap", "kinetic",1.5,-1,1000,90,50)
	_ammo("cannon_bc_ap", "kinetic",1.2,-1,1000,60,25)
	_ammo("cannon_a_he", "chemical",3,5,-1,5,0,2,50)
	_ammo("cannon_bc_he", "chemical",3,5,-1,5,0,2,40)
	_gun("pdw",200,30,"pdw")
	_gun("rifle",400,30,"standard")
	_gun("lmg",600,150,"standard")
	_gun("vehicle_mg",600,450,"standard")
	# Only previously confirmed shotgun fields; no invented damage/range/aim.
	var shotgun := WeaponDefinition.new()
	shotgun.definition_id = "shotgun"
	shotgun.capacity = 10
	shotgun.actual_round_interval = 1
	shotgun.game_projectile_interval = 1
	weapons["shotgun"] = shotgun
	_weapon("recoilless",600,1,2,2,0,["recoilless_ap","recoilless_he"])
	weapons.recoilless.indoor_qualification = 1
	weapons.recoilless.preparation_seconds = 6
	weapons.recoilless.game_projectile_interval = 0 # Per-round preparation owns cadence.
	_weapon("rocket",400,1,1,1,0,["rocket_ap"])
	weapons.rocket.indoor_qualification = 0
	weapons.rocket.preparation_seconds = 3
	weapons.rocket.game_projectile_interval = 0
	_weapon("cannon_a",TEST_A_RANGE_M,10,2,3,1,["cannon_a_ap","cannon_a_he"])
	weapons.cannon_a.temporary_fields.append("range_m")
	_weapon("cannon_b",1000,30,2,3,1,["cannon_bc_ap","cannon_bc_he"])
	_weapon("cannon_c",1000,30,2,3,1,["cannon_bc_ap","cannon_bc_he"])
	for name: String in ["cannon_a","cannon_b","cannon_c"]:
		weapons[name].consumption_per_projectile = 1 if name == "cannon_a" else 3
		weapons[name].actual_round_interval = 1 if name == "cannon_a" else 0.5
		weapons[name].game_projectile_interval = 1 if name == "cannon_a" else 1.5
		weapons[name].preparation_seconds = 4 if name == "cannon_a" else 3
		weapons[name].mechanical_loading = name == "cannon_a"
	for id: String in ["pdw","standard"]:
		ammunition[id].test_curve = "normalized_gun_log"
		ammunition[id].test_log_shape = TEST_GUN_LOG_SHAPE
	for id: String in ["cannon_a_ap","cannon_bc_ap"]: ammunition[id].test_curve = "baseline_cannon_log"
	for value: WeaponDefinition in weapons.values():
		value.reduction_ignore = 0
		value.temporary_fields.append("reduction_ignore")
		if value.definition_id in ["pdw","rifle","lmg","vehicle_mg"]: value.temporary_fields.append("ammo.test_curve_shape")
		if value.definition_id.begins_with("cannon_"): value.temporary_fields.append("ammo.explosion_radius_m")
	Prototype05FConfig.configure(weapons)
	# Legacy isolated regression fixtures: operator choices are TEST ONLY.
	for value: WeaponDefinition in weapons.values():
		value.required_operators = 1
		value.squad_weapon = value.definition_id in ["lmg","recoilless","shotgun"]
		value.preparation_cadence = value.definition_id in ["recoilless","rocket"]
		value.data_source = "test_only:legacy_05d"

func use_confirmed_performance() -> void:
	var data := ConfirmedGameData.new()
	var models := {"pdw":"W_MP7","rifle":"W_M4A1","lmg":"W_M249","vehicle_mg":"W_M249V","recoilless":"W_CG","rocket":"W_AT4","shotgun":"W_SHOTGUN","cannon_a":"W_MK44","cannon_b":"W_M242","cannon_c":"W_M242"}
	for alias: String in models:
		# Formal performance with missing fields preserved. No legacy fill-in.
		weapons[alias] = data.weapon(models[alias])
	default_inventory.clear()
	ammunition.clear()
	for alias: String in models:
		for ammo: AmmoDefinition in weapons[alias].ammo_definitions:
			ammunition[ammo.ammo_id] = ammo
		default_inventory[alias] = data.initial_inventory_for_weapon(models[alias]).inventory

func _ammo(id: String, kind: String, damage: float, upper: float, distance: float, penetration: float, module: float = 0, radius: float = -1, suppression: float = 0) -> void:
	var value := AmmoDefinition.new()
	value.ammo_id = id
	value.damage_type = kind
	value.nominal_damage = damage
	value.penetration_upper = upper
	value.anchor_distance_m = distance
	value.anchor_penetration = penetration
	value.module_damage = module
	value.explosion_radius_m = radius
	value.suppression = suppression
	value.curve_description = "logarithmic anchors only; coefficient undefined; floor 5" if distance > 0 else "constant chemical penetration"
	ammunition[id] = value

func _weapon(id: String, distance: float, capacity: int, low: float, high: float, moving: int, ammo: Array) -> void:
	var value := WeaponDefinition.new()
	value.definition_id = id
	value.range_m = distance
	value.capacity = capacity
	value.aim_min_seconds = low
	value.aim_max_seconds = high
	value.moving_aim_qualification = moving
	# Attack lists are explicit isolated-test values, not inferred from damage.
	value.allowed_target_types.assign([WeaponDefinition.TargetType.INFANTRY,WeaponDefinition.TargetType.GROUND_VEHICLE])
	value.temporary_fields.append("allowed_target_types")
	for ammo_id: String in ammo: value.ammo_definitions.append(ammunition[ammo_id])
	weapons[id] = value

func _gun(id: String, distance: float, capacity: int, ammo: String) -> void:
	_weapon(id,distance,capacity,TEST_AIM_SECONDS,TEST_AIM_SECONDS,1,[ammo])
	var value: WeaponDefinition = weapons[id]
	value.temporary_fields.append_array(["aim_min_seconds","aim_max_seconds","moving_aim_qualification"])
	value.consumption_per_projectile = 3
	value.actual_round_interval = 0.5
	value.game_projectile_interval = 1.5
	value.preparation_seconds = 3

func allocate(definition: UnitDefinition, weapon_id: String, kind: int, node_id: String, slot_id: String, inventory: Dictionary, primary: bool = false) -> void:
	if definition.configuration_source == "unconfigured": definition.configuration_source = "test_only:05d_allocation"
	var value := WeaponAllocation.new()
	value.definition = weapons[weapon_id]
	value.node_kind = kind
	value.member_id = int(node_id) if kind == WeaponAllocation.NodeKind.SOLDIER else 0
	value.mount_id = node_id if kind == WeaponAllocation.NodeKind.MOUNT else ""
	value.slot_id = slot_id
	value.initial_inventory = inventory.duplicate(true)
	value.initial_pending = 0 # Runtime applies the user-confirmed full-first-magazine rule.
	value.direction_primary = primary
	value.orientation_priority = 0 if weapon_id.begins_with("cannon_") else 1
	value.retention_priority = 0 if weapon_id in ["recoilless","lmg"] else 1 # Existing test unit configuration only.
	value.occupied_slots.assign(["primary","secondary"] if weapon_id == "recoilless" else [slot_id])
	definition.weapon_allocations.append(value)

func squad(assault: bool) -> UnitDefinition:
	var value := UnitDefinition.new()
	value.resource_name = "test_only_motorized_assault" if assault else "test_only_motorized_defense"
	value.configuration_source = "test_only:05d_squad"
	value.member_count = 8
	value.maximum_health = 40
	value.hardened_speed = 5
	value.unhardened_speed = 5
	value.turn_speed_degrees = 360
	value.protection_kinetic = 6
	value.protection_chemical = 6
	value.ability_tags.assign(["sprint","smoke_1"])
	for id: int in range(1,9):
		if id <= 2:
			var model := "recoilless" if assault else "lmg"
			var stock: Dictionary = default_inventory.get(model,{"recoilless_ap":4,"recoilless_he":4})
			allocate(value,model,WeaponAllocation.NodeKind.SOLDIER,str(id),"primary",stock,true)
		else: allocate(value,"rifle",WeaponAllocation.NodeKind.SOLDIER,str(id),"primary",default_inventory.rifle,true)
	if not assault:
		var stock := WeaponAllocation.new()
		stock.definition = weapons.rocket
		stock.node_kind = WeaponAllocation.NodeKind.UNASSIGNED_SQUAD_STOCK
		stock.initial_inventory = {"rocket_ap":5} if weapons.rocket.data_source.begins_with("test_only:") else {}
		value.weapon_allocations.append(stock)
	return value

# Isolated weapon-slot regression fixture, never a playable vehicle preset.
# No A/B/C unit identity, armor, HP, speed or capabilities are carried forward.
func weapon_slot_fixture(weapon_model: String) -> UnitDefinition:
	var value := UnitDefinition.new()
	value.resource_name = "isolated_weapon_slot_fixture"
	value.unit_type = UnitDefinition.UnitType.ARMORED_VEHICLE
	value.maximum_health = 10 # DB22 vehicle range lower bound, fixture only.
	for id: String in ["main","commander"]:
		var mount := WeaponMountDefinition.new()
		mount.mount_id = id
		mount.kind = WeaponMountDefinition.Kind.MAIN_TURRET if id == "main" else WeaponMountDefinition.Kind.WEAPON_STATION
		mount.rotation_speed_degrees = 120 if id == "main" else 360
		value.mounts.append(mount)
	allocate(value,"cannon_"+weapon_model,WeaponAllocation.NodeKind.MOUNT,"main","main",{"cannon_a_ap":10,"cannon_a_he":40} if weapon_model == "a" else {"cannon_bc_ap":30,"cannon_bc_he":120},true)
	allocate(value,"vehicle_mg",WeaponAllocation.NodeKind.MOUNT,"main","coax",{"standard":2250})
	allocate(value,"vehicle_mg",WeaponAllocation.NodeKind.MOUNT,"commander","mg",{"standard":2250},true)
	if weapon_model == "c": allocate(value,"vehicle_mg",WeaponAllocation.NodeKind.HULL,"hull","mg",{"standard":2250},true)
	return value
