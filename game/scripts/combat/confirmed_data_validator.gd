class_name ConfirmedDataValidator
extends RefCounted

# Export contract version is separate from game rules and DATA revision.
# Pin the confirmed workbook export, not ReplayContent/frozen v1 fingerprints.
const DATA_SCHEMA_VERSION := 1
const DATA_VERSION := "RTT_GAME_DATA-2026-10-06-40"
const RULES_ID := "DB-2026-10-06-40"
const SOURCE := "docs/RTT_GAME_DATA.xlsx"
const SOURCE_SHA256 := "0113889F5046869610F5195D7751A31A76D4417C208BD9019C25D9892D8C9AC0"
const ID_FIELDS := {"Weapons":"Weapon_ID","Ammo":"Ammo_ID","InfantrySquads":"Squad_ID","ArmoredVehicles":"Vehicle_ID","Parameters":"Parameter"}
const REQUIRED_COLUMNS := {
	"Weapons":["Weapon_ID","Weapon_Name","Class","Min_Range_m","Max_Range_m","Effective_ROF_rpm","Aggregation","Single_Weapon_Projectile_Interval_s","Capacity_rounds","Reload_s","Move_Fire","Indoor_Fire","Spread_Relative","Slot_Requirement","Required_Operators","Special_Equipment_Weight_t","Initial_Inventory_rounds","Aim_Time_Min_s","Aim_Time_Max_s","Preparation_Time_s"],
	"Ammo":["Ammo_ID","Weapon_ID","Ammo_Name","Damage_Type","D0","P0_or_Pc","Range_Anchor_m","P_at_R","Projectile_Speed_kmh","Blast_Radius_m","Suppression","Module_Damage","Initial_Inventory_rounds"],
	"InfantrySquads":["Squad_ID","Squad_Name","Squad_Size","HP_per_Soldier","Facing","Kinetic_Armor","Chemical_Armor","Record_Type"],
	"ArmoredVehicles":["Vehicle_ID","Vehicle_Name","HP","Front_Kinetic_Armor","Side_Kinetic_Armor","Rear_Kinetic_Armor","Top_Kinetic_Armor","Front_Chemical_Armor","Side_Chemical_Armor","Rear_Chemical_Armor","Top_Chemical_Armor","Record_Type"],
	"Parameters":["Parameter","Value","Unit"]
}

static func validate_snapshot(snapshot: Variant,actual_source_sha256: String = "") -> Dictionary:
	var errors: Array[Dictionary] = []
	if not snapshot is Dictionary:
		_add(errors,"$","invalid_document","Expected JSON object")
		return _result(errors,actual_source_sha256)
	for key: String in ["data_schema_version","data_version","rules_id","baseline_id","source","source_sha256","sheets"]:
		if not snapshot.has(key): _add(errors,key,"missing_metadata","Required export metadata is missing")
	if snapshot.get("data_schema_version") != DATA_SCHEMA_VERSION: _add(errors,"data_schema_version","unsupported_schema","Unsupported DATA schema version")
	if snapshot.get("data_version") != DATA_VERSION: _add(errors,"data_version","unsupported_data_version","Unrecognized confirmed export revision")
	if snapshot.get("rules_id") != RULES_ID: _add(errors,"rules_id","rules_mismatch","Export rules are incompatible")
	if snapshot.get("baseline_id") != snapshot.get("rules_id"): _add(errors,"baseline_id","legacy_rules_mismatch","Legacy rules alias differs from rules_id")
	if snapshot.get("source") != SOURCE: _add(errors,"source","source_mismatch","Unrecognized authoritative source")
	var claimed: Variant = snapshot.get("source_sha256")
	if not claimed is String or claimed.to_upper() != SOURCE_SHA256: _add(errors,"source_sha256","source_hash_mismatch","Export must identify the pinned confirmed workbook")
	if not actual_source_sha256.is_empty() and actual_source_sha256.to_upper() != SOURCE_SHA256: _add(errors,"source_sha256","actual_source_hash_mismatch","Available workbook does not match the pinned export")
	var sheets: Variant = snapshot.get("sheets")
	if not sheets is Dictionary:
		_add(errors,"sheets","invalid_sheets","Expected sheet-name object")
		return _result(errors,actual_source_sha256)
	var indexes := {}
	for sheet: String in ID_FIELDS:
		indexes[sheet] = {}
		var rows: Variant = sheets.get(sheet)
		if not rows is Array:
			_add(errors,"sheets."+sheet,"missing_or_invalid_sheet","Required sheet must be an array")
			continue
		if rows.is_empty(): _add(errors,"sheets."+sheet,"empty_sheet","Confirmed export sheet is empty")
		for i: int in rows.size():
			var row: Variant = rows[i]
			var path := "sheets.%s[%d]" % [sheet,i]
			if not row is Dictionary:
				_add(errors,path,"invalid_row","Expected a row object")
				continue
			for column: String in REQUIRED_COLUMNS[sheet]:
				if not row.has(column): _add(errors,path+"."+column,"missing_column","Required source column is missing")
			if sheet in ["Weapons","Ammo"] and row.has("Initial_Inventory_rounds"):
				var stock: Variant = row.Initial_Inventory_rounds
				var stock_valid: bool = stock in ["未配置","不适用"] if stock is String else (stock is float or stock is int) and is_finite(float(stock)) and float(stock) >= 0 and float(stock) == floor(float(stock))
				if not stock_valid: _add(errors,path+".Initial_Inventory_rounds","invalid_inventory_value","Stock must be a nonnegative integer or an explicit missing/N.A. marker")
			var id: Variant = row.get(ID_FIELDS[sheet])
			if not id is String or id.is_empty() or id.strip_edges() != id:
				_add(errors,path+"."+ID_FIELDS[sheet],"invalid_id","ID must be a nonempty string without surrounding whitespace")
			elif indexes[sheet].has(id):
				errors.append({"path":path+"."+ID_FIELDS[sheet],"code":"duplicate_id","id":id,"related_path":indexes[sheet][id],"message":"Duplicate stable source ID"})
			else: indexes[sheet][id] = path+"."+ID_FIELDS[sheet]
	if sheets.get("Ammo") is Array:
		for i: int in sheets.Ammo.size():
			var row: Variant = sheets.Ammo[i]
			if not row is Dictionary: continue
			var id: Variant = row.get("Weapon_ID")
			if not id is String or not indexes.Weapons.has(id): _add(errors,"sheets.Ammo[%d].Weapon_ID" % i,"missing_weapon_reference","Ammo compatibility references an absent weapon")
	# Existing adapter consumes this parameter by its source identity.
	if not indexes.Parameters.has("当前AT4班组配置数量上限"): _add(errors,"sheets.Parameters","missing_parameter_reference","AT4 configured-count parameter is missing")
	return _result(errors,actual_source_sha256)

static func _result(errors: Array[Dictionary],actual: String) -> Dictionary:
	return {"valid":errors.is_empty(),"errors":errors,"data_schema_version":DATA_SCHEMA_VERSION,
		"data_version":DATA_VERSION,"rules_id":RULES_ID,
		"source_verification":"actual_workbook_and_pinned_export" if not actual.is_empty() else "pinned_export_metadata",
		"scope":"export metadata, required tables/columns, stable IDs and references; not complete unit legality or workbook-cell comparison"}

static func _add(errors: Array[Dictionary],path: String,code: String,message: String) -> void:
	errors.append({"path":path,"code":code,"message":message})
