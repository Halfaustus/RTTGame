class_name ConfirmedGameData
extends RefCounted

# Checked-in DATA snapshot; no Excel runtime loading or temporary defaults.
const PATH := "res://data/confirmed/db29.json"
const ID_FIELDS := ConfirmedDataValidator.ID_FIELDS
var records: Dictionary = {}
var validation_report: Dictionary = {}
var _explicit_compatibility: Array[Dictionary] = []
var _has_explicit_compatibility := false

# Snapshot injection is for isolated tests; no caller writes formal DATA.
# Exported servers may omit the workbook: pin its metadata hash. If present,
# additionally verify the real file. This is distinct from Replay fingerprints.
func _init(snapshot: Variant = null,actual_source_sha256: String = "") -> void:
	var parsed: Variant = snapshot
	if parsed == null: parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	var actual := actual_source_sha256
	if snapshot == null and actual.is_empty() and FileAccess.file_exists("res://../"+ConfirmedDataValidator.SOURCE):
		actual = FileAccess.get_sha256("res://../"+ConfirmedDataValidator.SOURCE)
	validation_report = ConfirmedDataValidator.validate_snapshot(parsed,actual)
	if validation_report.valid:
		records = parsed.sheets.duplicate(true)
	elif snapshot == null:
		push_error("Confirmed DATA rejected: "+str(validation_report.errors))

# Complete relation replacement is explicit and transactional. Default callers
# still get exactly the legacy membership/order; no migration of Ammo rows.
func configure_compatibility(relations: Variant) -> Dictionary:
	var weapon_ids: Array = []
	var ammo_ids: Array = []
	for row: Dictionary in records.get("Weapons",[]): weapon_ids.append(row.Weapon_ID)
	for row: Dictionary in records.get("Ammo",[]): ammo_ids.append(row.Ammo_ID)
	var result := WeaponAmmoCompatibility.validate(relations,weapon_ids,ammo_ids)
	if result.valid:
		_explicit_compatibility.assign(relations.duplicate(true))
		_has_explicit_compatibility = true
	return result

func compatibility_relations() -> Array[Dictionary]:
	return _explicit_compatibility.duplicate(true) if _has_explicit_compatibility else WeaponAmmoCompatibility.from_legacy_rows(records.get("Ammo",[]))

func compatible_ammo_ids(id: String) -> Array[String]:
	return WeaponAmmoCompatibility.ammo_ids_for(compatibility_relations(),id)

# Sole DATA stock adapter for active configurations: Ammo column only.
# Weapons.Initial_Inventory_rounds is retained for source traceability and is
# deliberately NEVER summed/fallback-read here. Stock stays on allocations.
# Missing vs N/A remains explicit; neither is an implicit zero/refill.
func initial_inventory_for_weapon(id: String) -> Dictionary:
	var inventory := {}
	var missing: Array[Dictionary] = []
	var errors: Array[Dictionary] = []
	if record("Weapons",id).is_empty(): errors.append({"path":"Weapons."+id,"code":"unknown_weapon","message":"Weapon record is missing"})
	var ammo_ids := compatible_ammo_ids(id)
	if ammo_ids.is_empty(): errors.append({"path":"Weapons."+id+".ammo_definitions","code":"unconfigured_ammo_relation","message":"No ammo relationship is configured; do not infer zero stock"})
	for ammo_id: String in ammo_ids:
		var row := record("Ammo",ammo_id)
		# Only the existing export association carries a DATA default template.
		# Added compatibility grants no stock; its allocation must choose stock.
		if row.get("Weapon_ID") != id:
			missing.append({"ammo_id":ammo_id,"source_value":null,"path":"configuration.initial_inventory."+ammo_id,"reason":"explicit_configuration_required_for_reuse"})
			continue
		var count := number(row,"Initial_Inventory_rounds")
		if not is_finite(count):
			missing.append({"ammo_id":ammo_id,"source_value":row.get("Initial_Inventory_rounds"),"path":"Ammo."+ammo_id+".Initial_Inventory_rounds"})
		elif count < 0 or count != floor(count):
			errors.append({"path":"Ammo."+ammo_id+".Initial_Inventory_rounds","code":"invalid_initial_stock","message":"Configured inventory must be a nonnegative integer"})
		else: inventory[ammo_id] = int(count)
	return {"valid":errors.is_empty(),"complete":errors.is_empty() and missing.is_empty(),"inventory":inventory,"missing":missing,"errors":errors,"source":"Ammo.Initial_Inventory_rounds"}

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
	ammo.distance_selected_launch = record("Weapons",str(row.get("Weapon_ID",""))).get("Class","") == "迫击炮"
	if ammo.distance_selected_launch: ammo.initial_speed_mps = NAN
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

# Redundant cadence conflicts never silently become firing definitions.
func weapon(id: String) -> WeaponDefinition:
	var value := _weapon_from_record(id)
	return value if value != null and value.cadence_issues().is_empty() else null

func weapon_validation_issues(id: String) -> Array[Dictionary]:
	var value := _weapon_from_record(id)
	if value == null: return [{"code":"unknown_weapon","path":"Weapons."+id,"message":"Weapon record does not exist"}]
	var issues := value.cadence_issues()
	for issue: Dictionary in issues:
		issue.path = "Weapons."+id+".Single_Weapon_Projectile_Interval_s"
		issue["source_fields"] = ["Effective_ROF_rpm","Aggregation","Single_Weapon_Projectile_Interval_s"]
	return issues

func _weapon_from_record(id: String) -> WeaponDefinition:
	var row := record("Weapons",id)
	if row.is_empty(): return null
	var value := WeaponDefinition.new()
	value.definition_id = id
	value.caliber_mm = number(row,"Caliber_mm") # Absent formal field remains NAN.
	value.data_source = "DB40:RTT_GAME_DATA.xlsx"
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
	for ammo_id: String in compatible_ammo_ids(id):
		# One source row per Ammo_ID, independent of how many weapons reference it.
		# Materialized mutable Resources retain existing per-call isolation.
		value.ammo_definitions.append(ammunition(ammo_id))
	# Attack types, spread, ignore and installation remain unconfigured.
	return value

func squad_configuration(id: String) -> Dictionary:
	var row := record("InfantrySquads",id)
	return {"reason":"unknown_squad"} if row.is_empty() else {"reason":"squad_configuration_missing","record":row,"missing_fields":["Squad_Size","weapon_allocations"]}
