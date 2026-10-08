class_name BattleHUD
extends Control

signal command_requested(command: String)
signal unit_requested(unit_id: int)
signal locate_requested(unit_id: int)
signal group_requested(group: int, additive: bool)
const BOTTOM_HEIGHT := 190.0
const MAP_WIDTH := 200.0
const SUMMARY_WIDTH := 220.0
const COMMAND_WIDTH := 240.0
const MESSAGE_WIDTH := 300.0
const MESSAGE_SECONDS := 8.0
const MAX_MESSAGES := 100
var _data := ConfirmedGameData.new()
var _weapons: HBoxContainer
var _summary: Label
var _unit_tabs: HBoxContainer
var _unit_buttons := {}
var _commands: Array[Button] = []
var _messages: VBoxContainer
var _history: Button
var _message_rows: Array[Dictionary] = []
var _history_open := false
var _minimap: BattleMinimap
var _weapon_panels := {}
var _group_buttons: Array[Button] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bottom := PanelContainer.new()
	bottom.name = "BottomHUD"
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -BOTTOM_HEIGHT
	add_child(bottom)
	var row := HBoxContainer.new()
	bottom.add_child(row)
	_minimap = BattleMinimap.new()
	_minimap.custom_minimum_size = Vector2(MAP_WIDTH, BOTTOM_HEIGHT)
	_minimap.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(_minimap)
	var groups := GridContainer.new()
	groups.name = "ControlGroups"
	groups.columns = 2
	groups.custom_minimum_size = Vector2(76, BOTTOM_HEIGHT)
	groups.add_theme_constant_override("h_separation", 4)
	groups.add_theme_constant_override("v_separation", 4)
	row.add_child(groups)
	for index: int in 10:
		var group := (index + 1) % 10
		var button := Button.new()
		button.text = str(group)
		button.custom_minimum_size = Vector2(32, 32)
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 16)
		button.add_theme_stylebox_override("normal", _group_style(Color.WHITE))
		button.add_theme_stylebox_override("hover", _group_style(Color.WHITE))
		button.add_theme_stylebox_override("pressed", _group_style(Color.WHITE))
		button.add_theme_stylebox_override("disabled", _group_style(Color(0.45, 0.45, 0.45)))
		button.pressed.connect(func(): group_requested.emit(group, Input.is_key_pressed(KEY_SHIFT)))
		groups.add_child(button)
		_group_buttons.append(button)
	var scroll := ScrollContainer.new()
	scroll.name = "Weapons"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	_weapons = HBoxContainer.new()
	scroll.add_child(_weapons)
	_summary = Label.new()
	_summary.name = "UnitSummary"
	_summary.custom_minimum_size.x = SUMMARY_WIDTH
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var summary_box := VBoxContainer.new()
	summary_box.custom_minimum_size.x = SUMMARY_WIDTH
	row.add_child(summary_box)
	var unit_scroll := ScrollContainer.new()
	unit_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	summary_box.add_child(unit_scroll)
	_unit_tabs = HBoxContainer.new()
	unit_scroll.add_child(_unit_tabs)
	summary_box.add_child(_summary)
	var grid := GridContainer.new()
	grid.name = "FixedCommands"
	grid.columns = 3
	grid.custom_minimum_size.x = COMMAND_WIDTH
	row.add_child(grid)
	for index: int in 9:
		var button := Button.new()
		button.custom_minimum_size = Vector2(76, 54)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func():
			var command := str(button.get_meta("command", ""))
			if not command.is_empty(): command_requested.emit(command))
		grid.add_child(button)
		_commands.append(button)
	var message_panel := PanelContainer.new()
	message_panel.name = "BattleMessages"
	message_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	message_panel.offset_left = -MESSAGE_WIDTH
	message_panel.offset_top = 52
	message_panel.offset_right = -12
	message_panel.offset_bottom = 300
	add_child(message_panel)
	var message_box := VBoxContainer.new()
	message_panel.add_child(message_box)
	_history = Button.new()
	_history.text = "战场信息 · 展开历史"
	_history.focus_mode = Control.FOCUS_NONE
	_history.pressed.connect(func():
		_history_open = not _history_open
		_history.text = "战场信息 · 收起历史" if _history_open else "战场信息 · 展开历史"
		_refresh_messages())
	message_box.add_child(_history)
	var message_scroll := ScrollContainer.new()
	message_scroll.custom_minimum_size.y = 180
	message_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	message_box.add_child(message_scroll)
	_messages = VBoxContainer.new()
	_messages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message_scroll.add_child(_messages)
	show_selection([], {}, 0)
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.timeout.connect(_refresh_messages)
	add_child(timer)
	timer.start()

func configure_map(bounds: Rect2) -> void:
	_minimap.bounds = bounds

func _group_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.04, 0.04, 0.75)
	style.border_color = color
	style.set_border_width_all(1)
	style.set_corner_radius_all(0)
	return style

func show_control_groups(groups: Dictionary, selection: Array[int], available: Array[int]) -> void:
	for index: int in _group_buttons.size():
		var group := (index + 1) % 10
		var members: Array[int] = []
		for id: int in groups.get(group, []):
			if available.has(id) and not members.has(id): members.append(id)
		var enabled := not members.is_empty()
		_group_buttons[index].disabled = not enabled
		_group_buttons[index].modulate = Color.WHITE if enabled else Color(0.55, 0.55, 0.55)
		var selected := enabled and members.size() == selection.size()
		if selected:
			for id: int in members:
				if not selection.has(id): selected = false; break
		_group_buttons[index].add_theme_stylebox_override("normal", _group_style(Color(1.0, 0.78, 0.2) if selected else Color.WHITE))

func update_map(units: Array[Dictionary], viewer: int) -> void:
	_minimap.update_units(units, viewer)

func _clear_children(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _name_for(sheet: String, id: String) -> String:
	var record := _data.record(sheet, id)
	return str(record.get("Weapon_Name" if sheet == "Weapons" else "Ammo_Name", id))

func show_selection(units: Array[Dictionary], structures: Dictionary, viewer: int) -> void:
	var active := {}
	var unit_ids := BattleHUDModel.selection_order(units)
	for id: int in _unit_buttons.keys():
		if unit_ids.has(id): continue
		_unit_tabs.remove_child(_unit_buttons[id])
		_unit_buttons[id].queue_free()
		_unit_buttons.erase(id)
	for index: int in unit_ids.size():
		var id: int = unit_ids[index]
		if not _unit_buttons.has(id):
			var button := Button.new()
			button.text = "#%d" % id
			button.focus_mode = Control.FOCUS_NONE
			button.pressed.connect(func(): unit_requested.emit(id))
			_unit_tabs.add_child(button)
			_unit_buttons[id] = button
		_unit_tabs.move_child(_unit_buttons[id], index)
	_summary.text = "未选择单位"
	if units.size() == 1:
		var unit := units[0]
		_summary.text = "%s\n%s\n生命 %.1f / %.1f" % [unit.get("name", "名称未配置"), unit.get("configuration", "配置未配置"), unit.health, unit.maximum_health]
		if int(unit.unit_type) == UnitDefinition.UnitType.INFANTRY:
			_summary.text += "\n人数 %s / %s" % [str(unit.get("member_count", "未同步")), str(unit.get("maximum_members", "未配置"))]
	elif units.size() > 1:
		_summary.text = "已选择 %d 个单位" % units.size()
	for unit: Dictionary in units:
		var rows := BattleHUDModel.weapons(unit, structures.get(int(unit.unit_id), {}), viewer)
		if rows.is_empty():
			var key := "%d/unavailable" % unit.unit_id
			active[key] = true
			if not _weapon_panels.has(key):
				var label := Label.new()
				label.text = "#%d\n武器信息未提供" % unit.unit_id
				_weapons.add_child(label)
				_weapon_panels[key] = {"node":label}
		for weapon: Dictionary in rows:
			var key := "%d/%s" % [unit.unit_id, weapon.definition_id]
			active[key] = true
			if not _weapon_panels.has(key):
				var box := VBoxContainer.new()
				box.custom_minimum_size.x = 140
				_weapons.add_child(box)
				var heading := Label.new()
				box.add_child(heading)
				var ammunition := HBoxContainer.new()
				box.add_child(ammunition)
				_weapon_panels[key] = {"node":box, "title":heading, "ammo_row":ammunition, "ammo_labels":{}, "progress_labels":[]}
			var panel: Dictionary = _weapon_panels[key]
			var title: Label = panel.title
			title.text = ("#%d\n" % unit.unit_id if units.size() > 1 else "") + "%s×%d" % [_name_for("Weapons", weapon.definition_id), weapon.count]
			for ammo: String in weapon.inventory:
				if not panel.ammo_labels.has(ammo):
					var label := Label.new()
					panel.ammo_row.add_child(label)
					panel.ammo_labels[ammo] = label
				var stock: Label = panel.ammo_labels[ammo]
				stock.text = "%s\n剩余 %d" % [_name_for("Ammo", ammo), weapon.inventory[ammo]]
				stock.modulate = Color(0.5, 0.5, 0.5) if int(weapon.inventory[ammo]) == 0 else Color.WHITE
			for ammo: String in panel.ammo_labels.keys():
				if not weapon.inventory.has(ammo):
					panel.ammo_row.remove_child(panel.ammo_labels[ammo])
					panel.ammo_labels[ammo].queue_free()
					panel.ammo_labels.erase(ammo)
			while panel.progress_labels.size() > weapon.channels.size():
				var label: Label = panel.progress_labels.pop_back()
				panel.node.remove_child(label)
				label.queue_free()
			for index: int in weapon.channels.size():
				var channel: Dictionary = weapon.channels[index]
				if index >= panel.progress_labels.size():
					var label := Label.new()
					panel.node.add_child(label)
					panel.progress_labels.append(label)
				var progress: Label = panel.progress_labels[index]
				progress.text = "瞄准 %d%%" % int(clampf(float(channel.aim_progress), 0, 1) * 100)
				if channel.loading: progress.text += " · 装填 %d%%" % int(clampf(float(channel.loading_progress), 0, 1) * 100)
	for key: String in _weapon_panels.keys():
		if active.has(key): continue
		_weapons.remove_child(_weapon_panels[key].node)
		_weapon_panels[key].node.queue_free()
		_weapon_panels.erase(key)
	var at := 0
	for key: String in active:
		_weapons.move_child(_weapon_panels[key].node, at)
		at += 1
	var slots := BattleHUDModel.command_slots(units, viewer)
	var labels := {"fast":"快速\nF", "attack_move":"攻击移动\nQ", "reverse":"倒车\nR", "ground_fire":"强制开火\nG", "artillery":"火炮\nT"}
	for index: int in 9:
		_commands[index].text = labels.get(slots[index], "")
		_commands[index].disabled = slots[index].is_empty()
		_commands[index].set_meta("command", slots[index])

func post_message(reason: String, unit_ids: Array = []) -> void:
	if reason.is_empty(): return
	var now := Time.get_ticks_msec() / 1000.0
	for row: Dictionary in _message_rows:
		if row.reason == reason and now - row.time < MESSAGE_SECONDS:
			for id: Variant in unit_ids:
				if not row.unit_ids.has(id): row.unit_ids.append(id)
			row.time = now
			_refresh_messages()
			return
	_message_rows.append({"reason":reason, "unit_ids":unit_ids.duplicate(), "time":now})
	if _message_rows.size() > MAX_MESSAGES: _message_rows.pop_front()
	_refresh_messages()

func _refresh_messages() -> void:
	if _messages == null: return
	_clear_children(_messages)
	var now := Time.get_ticks_msec() / 1000.0
	for row: Dictionary in _message_rows:
		var age: float = now - float(row.time)
		if not _history_open and age >= MESSAGE_SECONDS: continue
		var label := Label.new()
		label.text = str(row.reason)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = MESSAGE_WIDTH - 32
		if not _history_open: label.modulate.a = clampf(MESSAGE_SECONDS - age, 0, 1)
		_messages.add_child(label)
		for id: Variant in row.unit_ids:
			var locate := Button.new()
			locate.text = "定位 #%s" % str(id)
			locate.focus_mode = Control.FOCUS_NONE
			locate.pressed.connect(func(): locate_requested.emit(int(id)))
			_messages.add_child(locate)

func clear_session() -> void:
	_message_rows.clear()
	_history_open = false
	_history.text = "战场信息 · 展开历史"
	_refresh_messages()
	show_selection([], {}, 0)
	show_control_groups({}, [], [])
	update_map([], 0)
