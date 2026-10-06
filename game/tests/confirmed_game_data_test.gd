extends SceneTree

var failures := 0
var checks := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func _initialize() -> void:
	var data := ConfirmedGameData.new()
	check(data.records.size() == 5,"five DATA sheets")
	check(data.records.InfantrySquads.size() == 3 and data.records.ArmoredVehicles.size() == 3,"six confirmed unit records")
	for row: Dictionary in data.records.InfantrySquads:
		check(row.Record_Type == "已确认" and row.HP_per_Soldier == 5 and is_nan(data.number(row,"Squad_Size")),"confirmed infantry with unresolved size")
	for row: Dictionary in data.records.ArmoredVehicles:
		check(row.Record_Type == "已确认" and row.HP >= 10 and row.HP <= 20,"confirmed vehicle")
	check(data.record("ArmoredVehicles","B").Front_Chemical_Armor == 250,"vehicle B chemical protection")
	check(data.record("ArmoredVehicles","C").HP == 16,"vehicle C HP")
	check(is_equal_approx(data.weapon("W_M4A1").game_projectile_interval,7.2),"M4A1 single interval")
	check(is_equal_approx(data.weapon("W_M249").game_projectile_interval,2.4),"M249 single interval")
	check(data.weapon("W_M4A1").allowed_target_types.is_empty() and data.weapon("W_M4A1").projectile == null,"no invented eligibility or projectile")
	check(data.weapon("W_AT4").capacity == -1 and is_nan(data.weapon("W_AT4").game_projectile_interval),"missing AT4 config blocks fire")
	check(data.record("Weapons","W_AT4").Effective_ROF_rpm == "不适用" and data.record("Weapons","W_AT4").Preparation_Time_s == "未配置","missing and not applicable preserved")
	check(is_nan(data.number(data.record("Ammo","A_CG_HE"),"Projectile_Speed_kmh")),"missing speed never zero")
	check(data.weapon("W_MK44").capacity == 20 and data.weapon("W_MK44").mechanical_loading,"Mk44 capacity and loading")
	for row: Dictionary in data.records.Ammo:
		var ammo := data.ammunition(row.Ammo_ID)
		check(ammo.nominal_damage == row.D0 and ammo.suppression == row.Suppression and ammo.module_damage == row.Module_Damage,"confirmed ammo "+ammo.ammo_id)
		if ammo.damage_type == "kinetic":
			check(is_equal_approx(AmmoSelection.penetration(ammo,0),row.P0_or_Pc),"near anchor "+ammo.ammo_id)
			check(is_equal_approx(AmmoSelection.penetration(ammo,row.Range_Anchor_m),row.P_at_R),"range anchor "+ammo.ammo_id)
			check(AmmoSelection.penetration(ammo,row.Range_Anchor_m*2) < row.P_at_R or row.P_at_R == 5,"decay beyond anchor "+ammo.ammo_id)
	var rifle := data.ammunition("A_556")
	check(AmmoSelection.expected_damage(rifle,5,10,0,0) == 0.5,"kinetic no obsolete half-armor cutoff")
	check(AmmoSelection.expected_damage(rifle,20,10,0,0) == 1,"overpenetration capped")
	var copy := data.record("ArmoredVehicles","A")
	copy.HP = 0
	check(data.record("ArmoredVehicles","A").HP == 14,"record mutation isolated")
	print("Confirmed DATA: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
