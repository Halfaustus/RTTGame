extends SceneTree

var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if value: print("PASS 0.7A: ", label)
	else:
		failures += 1
		push_error("FAIL 0.7A: " + label)

func _run() -> void:
	var unit := {"unit_id":7, "owner_player_id":10, "unit_type":UnitDefinition.UnitType.INFANTRY,
		"armed":true, "health":15.0, "maximum_health":20.0, "member_count":3, "maximum_members":4,
		"name":"TEST ONLY", "configuration":"test.config", "direct_fire":true}
	var structure := {"unit_id":7, "weapons":[
		{"definition_id":"test.rifle", "operable_count":3, "configured_count":4, "pending_rounds":20,
			"inventory":{"test.ap":30,"test.he":0}, "aim_progress":0.5,"fire":{"loading":true,"loading_progress":0.25}},
		{"definition_id":"test.rifle", "operable_count":1,"inventory":{"test.ap":12,"test.he":0}},
		{"definition_id":"test.other", "operable_count":1,"inventory":{"test.other.ap":4}}]}
	var original := structure.duplicate(true)
	var rows := BattleHUDModel.weapons(unit, structure, 10)
	check(rows.size() == 2, "same definitions merge independently of installation")
	var rifle: Dictionary = rows[1]
	check(rifle.definition_id == "test.rifle" and rifle.count == 4, "current operable quantity does not promote fixed N")
	check(rifle.inventory["test.ap"] == 42, "inventory summed once, pending rounds not added")
	check(rifle.inventory.has("test.he") and rifle.inventory["test.he"] == 0, "depleted ammo remains present")
	check(rifle.channels.size() == 2 and rifle.channels[0].aim_progress == 0.5, "independent channels retain progress")
	check(structure == original, "projection leaves authoritative input unchanged")
	check(BattleHUDModel.weapons(unit, structure, 11).is_empty(), "other player cannot inspect private weapons")
	check(BattleHUDModel.weapons(unit, structure, 0).is_empty(), "unresolved player identity fails closed")
	var mismatched := structure.duplicate(true)
	mismatched.unit_id = 8
	check(BattleHUDModel.weapons(unit, mismatched, 10).is_empty(), "mismatched structure identity rejected")
	check(BattleHUDModel.weapons(unit, {}, 10).is_empty(), "missing structure not inferred")
	var slots := BattleHUDModel.command_slots([unit], 10)
	check(slots.size() == 9 and slots[0] == "" and slots[2] == "", "infantry gets neither fast movement nor reverse")
	check(slots[1] == "attack_move" and slots[4] == "ground_fire", "armed direct unit has existing command entries")
	for index: int in [3,5,6,7,8]: check(slots[index] == "", "unsupported ability retains fixed empty slot %d" % index)
	var armored := unit.duplicate()
	armored.unit_type = UnitDefinition.UnitType.ARMORED_VEHICLE
	armored.armed = false
	armored.direct_fire = false
	slots = BattleHUDModel.command_slots([armored], 10)
	check(slots[0] == "fast" and slots[2] == "reverse" and slots[1] == "", "unarmed armor only has movement qualification")
	check(BattleHUDModel.command_slots([unit], 11).all(func(value): return value == ""), "foreign commands absent")
	var dead := unit.duplicate()
	dead.health = 0
	check(BattleHUDModel.command_slots([dead], 10).all(func(value): return value == ""), "dead unit has no commands")
	var bounds := Rect2(-200,-200,400,400)
	var area := Rect2(8,8,184,174)
	check(BattleHUDModel.map_point(Vector3.ZERO,bounds,area).is_equal_approx(area.get_center()), "map center uses existing bounds")
	check(BattleHUDModel.map_point(Vector3(-200,0,-200),bounds,area) == area.position, "map minimum projects correctly")
	check(BattleHUDModel.map_point(Vector3(500,0,500),bounds,area) == area.end, "map positions bounded by drawing area")
	var entries: Array[Dictionary] = [
		{"unit_id":4,"group_category":"aircraft","configuration":"a","health":1},
		{"unit_id":2,"group_category":"infantry","configuration":"b","health":1},
		{"unit_id":3,"group_category":"recon","configuration":"z","health":1},
		{"unit_id":1,"group_category":"infantry","configuration":"a","health":1}]
	check(BattleHUDModel.selection_order(entries) == [3,1,2,4], "explicit category then configuration orders selection")
	entries[1].health = 0.1
	check(BattleHUDModel.selection_order(entries) == [3,1,2,4], "status change does not reorder selection")
	var hud := BattleHUD.new()
	root.add_child(hud)
	check(hud._commands.size() == 9, "real HUD builds fixed grid")
	check(hud.get_node("BottomHUD").get_child(0).get_child(0) is BattleMinimap, "minimap is leftmost bottom area")
	check(hud._weapons.get_parent().vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "weapon area is one horizontal row")
	hud.show_selection([unit], {7:structure}, 10)
	check(hud._summary.text.contains("人数 3 / 4"), "summary shows authoritative current/full personnel")
	check(not hud._summary.text.contains("恐慌") and not hud._summary.text.contains("装填"), "summary does not repeat badge state")
	var panel: Dictionary = hud._weapon_panels["7/test.rifle"]
	var original_panel: Node = panel.node
	check(panel.ammo_labels["test.he"].modulate.r == 0.5, "depleted ammo visible in gray")
	structure.weapons[0].inventory["test.ap"] = 27
	hud.show_selection([unit], {7:structure}, 10)
	check(hud._weapon_panels["7/test.rifle"].node == original_panel, "frequent snapshots reuse controls")
	check(panel.ammo_labels["test.ap"].text.ends_with("39"), "reused stock label updates")
	var requested: Array[int] = []
	hud.unit_requested.connect(func(id): requested.append(id))
	hud._unit_buttons[7].pressed.emit()
	check(requested == [7], "unit entry requests focus without changing authoritative state")
	var commands: Array[String] = []
	hud.command_requested.connect(func(value): commands.append(value))
	hud._commands[4].pressed.emit()
	check(commands == ["ground_fire"], "button emits original command intent only")
	hud.show_selection([unit], {7:structure}, 11)
	check(hud._weapon_panels.has("7/unavailable") and not hud._weapon_panels.has("7/test.rifle"), "foreign selection erases private UI content")
	hud.post_message("TEST ONLY rejection", [7])
	hud.post_message("TEST ONLY rejection", [7,8])
	check(hud._message_rows.size() == 1 and hud._message_rows[0].unit_ids == [7,8], "repeat reasons merge unique unit locations")
	hud._history.pressed.emit()
	check(hud._history_open, "message history expands")
	hud.configure_map(bounds)
	hud.update_map([{"unit_id":7,"position":Vector3.ZERO}],10)
	check(hud._minimap.units.size() == 1, "map accepts only supplied presentation list")
	hud.clear_session()
	check(hud._minimap.units.is_empty() and hud._weapon_panels.is_empty() and hud._message_rows.is_empty(), "session reset removes all HUD state")
	check(hud._summary.text == "未选择单位" and hud._commands.all(func(button): return button.disabled), "reset clears summary and command qualification")
	hud.free()
	await process_frame
	print("0.7A checks: %d, failures: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)
