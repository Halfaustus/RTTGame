class_name ConfirmedGameData
extends RefCounted

# Checked-in DATA snapshot; no Excel runtime loading or temporary defaults.
const PATH := "res://data/confirmed/db29.json"
const ID_FIELDS := {"Weapons":"Weapon_ID","Ammo":"Ammo_ID","InfantrySquads":"Squad_ID","ArmoredVehicles":"Vehicle_ID","Parameters":"Parameter"}
var records: Dictionary = {}

func _init() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if parsed is Dictionary and parsed.get("baseline_id") == "DB-2026-10-05-29":
		records = parsed.sheets
	else:
		push_error("Confirmed DATA snapshot missing or incompatible")

func record(sheet: String, id: String) -> Dictionary:
	for row: Dictionary in records.get(sheet,[]):
		if str(row.get(ID_FIELDS.get(sheet,""),"")) == id: return row.duplicate(true)
	return {}

func number(row: Dictionary, field: String) -> float:
	var value: Variant = row.get(field)
	return float(value) if value is float or value is int else NAN

func ammunition(id: String) -> AmmoDefinition:
	var row := record("Ammo",id)
	if row.is_empty(): return null
	var ammo := AmmoDefinition.new()
	ammo.ammo_id = id
	ammo.initial_speed_mps = number(row,"Projectile_Speed_kmh") / 3.6
	ammo.damage_type = "kinetic" if row.Damage_Type == "动能" else "chemical"
	ammo.nominal_damage = number(row,"D0")
	ammo.penetration_upper = number(row,"P0_or_Pc")
	ammo.anchor_distance_m = number(row,"Range_Anchor_m")
	ammo.anchor_penetration = number(row,"P_at_R") if ammo.damage_type == "kinetic" else ammo.penetration_upper
	ammo.explosion_radius_m = number(row,"Blast_Radius_m")
	ammo.suppression = number(row,"Suppression")
	ammo.module_damage = number(row,"Module_Damage")
	ammo.curve_description = "DB29 logarithmic anchors" if ammo.damage_type == "kinetic" else "constant chemical penetration"
	ammo.configure_confirmed_curve()
	return ammo

func weapon(id: String) -> WeaponDefinition:
	var row := record("Weapons",id)
	if row.is_empty(): return null
	var value := WeaponDefinition.new()
	value.definition_id = id
	value.data_source = "DB29:RTT_GAME_DATA.xlsx"
	var operators := number(row,"Required_Operators")
	value.required_operators = int(operators) if is_finite(operators) else -1
	if id == "W_AT4": value.maximum_squad_count = int(number(record("Parameters","当前AT4班组配置数量上限"),"Value"))
	value.squad_weapon = row.Class not in ["步枪","一次性发射器"]
	value.preparation_cadence = id in ["W_AT4","W_CG"]
	value.range_m = number(row,"Max_Range_m")
	value.game_projectile_interval = number(row,"Single_Weapon_Projectile_Interval_s")
	var rpm := number(row,"Effective_ROF_rpm")
	value.actual_round_interval = 60.0/rpm if is_finite(rpm) and rpm > 0 else NAN
	value.consumption_per_projectile = 3 if row.Aggregation == "3发合1" else 1
	var capacity := number(row,"Capacity_rounds")
	# Missing capacity explicitly blocks FireSimulation; it grants no readiness.
	value.capacity = int(capacity) if is_finite(capacity) else -1
	value.preparation_seconds = number(row,"Reload_s")
	if value.preparation_cadence:
		value.preparation_seconds = number(row,"Preparation_Time_s")
		value.game_projectile_interval = 0.0 if is_finite(value.preparation_seconds) else NAN
	value.aim_min_seconds = number(row,"Aim_Time_Min_s")
	value.aim_max_seconds = number(row,"Aim_Time_Max_s")
	value.moving_aim_qualification = int(row.Move_Fire) if row.Move_Fire is bool else -1
	value.indoor_qualification = int(row.Indoor_Fire) if row.Indoor_Fire is bool else -1
	value.mechanical_loading = id == "W_MK44"
	for entry: Dictionary in records.get("Ammo",[]):
		if entry.Weapon_ID == id: value.ammo_definitions.append(ammunition(entry.Ammo_ID))
	# Attack types, spread, ignore and installation remain unconfigured.
	return value

func squad_configuration(id: String) -> Dictionary:
	var row := record("InfantrySquads",id)
	return {"reason":"unknown_squad"} if row.is_empty() else {"reason":"squad_configuration_missing","record":row,"missing_fields":["Squad_Size","weapon_allocations"]}
