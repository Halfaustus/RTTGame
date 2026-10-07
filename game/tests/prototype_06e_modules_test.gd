extends SceneTree

var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func run() -> void:
	var state := VehicleModuleState.new()
	var first := func(ids: Array[int]): return ids[0] # TEST ONLY deterministic plan injection, not production random policy.
	check(VehicleModuleState.eligible({"damage_type":"kinetic","module_damage":100},10,10).eligible,"kinetic inclusive qualification")
	check(not VehicleModuleState.eligible({"damage_type":"kinetic","module_damage":100},9.99,10).eligible,"kinetic below armor")
	check(VehicleModuleState.eligible({"damage_type":"chemical","module_damage":100},5,10).eligible,"chemical half armor inclusive")
	check(not VehicleModuleState.eligible({"damage_type":"chemical","module_damage":100},4.99,10).eligible,"chemical below half armor")
	check(not VehicleModuleState.eligible({"damage_type":"chemical","module_damage":0},1000,10).eligible,"HE no destruction accumulation")
	check(not VehicleModuleState.eligible({"damage_type":"kinetic","module_damage":null},10,10).ok,"missing is not zero")
	var plan := state.prepare("one",250,first)
	check(plan.ok and state.levels == [0,0,0,0] and state.amount == 0,"preparation is pure")
	check(state.commit(plan) and state.levels == [2,0,0,0] and state.amount == 50,"multiple levels preserve remainder")
	check(not state.commit(plan) and not state.prepare("one",100,first).ok,"stable event cannot double commit")
	plan = state.prepare("all",10000,first)
	check(plan.ok and plan.upgrades.size() == 6 and state.commit(plan),"single attack fills all remaining six levels")
	check(state.levels == [2,2,2,2] and state.amount == 0 and state.candidates().is_empty(),"all heavy discards excess")
	plan = state.prepare("heavy",50,Callable())
	check(plan.ok and state.commit(plan) and state.amount == 0,"all heavy stops accumulation")
	check(not state.repair_level_completed(-1) and state.amount == 0,"invalid repair rejected")
	check(state.repair_level_completed(VehicleModuleState.Module.LOADING) and state.amount == 0,"completed repair lowers one level and resets amount")
	plan = state.prepare("after-repair",125,first)
	check(plan.ok and plan.upgrades[0].module == VehicleModuleState.Module.LOADING and state.commit(plan) and state.amount == 0,"repaired candidate can be damaged anew")
	state = VehicleModuleState.new()
	check(not state.prepare("no-policy",100,Callable()).ok and state.amount == 0,"missing random decision never defaults")
	var invalid := func(_ids): return 9
	check(not state.prepare("invalid",100,invalid).ok and state.levels == [0,0,0,0],"invalid selector cannot mutate state")
	state.levels.assign([1,2,1,2])
	var modifiers := state.modifiers()
	check(modifiers.aim_time_multiplier == 10 and modifiers.spread_multiplier == 5,"optics and personnel multiply")
	check(modifiers.personnel_load_multiplier == 5 and modifiers.loading_module_multiplier == 2,"separate factors preserve mechanical exception")
	check(modifiers.vision == 0.5 and modifiers.movement == 0.2,"only optics/mobility affect sight/speed")
	check(not state.prepare("nan",NAN,first).ok,"nonfinite rejected")
	print("06E MODULES: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
