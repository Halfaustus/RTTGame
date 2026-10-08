extends Node3D

const UNIT_SCENE: PackedScene = preload("res://scenes/units/unit.tscn")
const MOVEMENT_CONFIG: MovementConfig = preload("res://data/prototype_movement.tres")
const UNIT_PICK_MASK: int = 2
const PICK_DISTANCE: float = 1000.0
const DRAG_THRESHOLD: float = 8.0
const SELECTION_RECTANGLE: Script = preload("res://scripts/core/selection_rectangle.gd")
const MOVEMENT_PATH_VISUAL: Script = preload("res://scripts/core/movement_path_visual.gd")
const SHOT_VISUAL: Script = preload("res://scripts/core/shot_visual.gd")

@export var replay_mode := false
@export var movement_config: MovementConfig = MOVEMENT_CONFIG
var presentation_source: PresentationFeed
var view_player_id := 0

var _visual_units: Dictionary[int, Node3D] = {}
var _selected_units: Dictionary[int, Node3D] = {}
var _move_targets: Dictionary[int, Vector3] = {}
var _movement_paths: Dictionary[int, MeshInstance3D] = {}
var _route_points: Dictionary[int, PackedVector3Array] = {}
var _route_progress: Dictionary[int, int] = {}
var _path_modes: Dictionary[int,int] = {}
var _pending_actions: Array[Dictionary] = []
var _fire_mode := "" # Minimal G ground / T single-point-one-shot interaction.
var _right_pressed := false
var _right_start: Vector2
var _right_ground: Variant
var _right_dragging := false
var _right_mode := MovementSimulation.MoveMode.BASIC
var _formation_preview: Node3D
var _left_pressed: bool = false
var _box_dragging: bool = false
var _drag_start: Vector2
var _drag_shift := false
var _selection_rectangle: Control
var _dead_units: Dictionary[int, bool] = {}
var _fast_move_armed: bool = false
var _attack_move_armed: bool = false
var _reverse_move_armed: bool = false
var _movement_mode_hint: Label
var _deployment_ui: DeploymentUI
var _unit_markers: Dictionary[int, UnitMarker] = {}
var _marker_layer: Control
var _selection_collection: Dictionary[int, Node3D] = {}
var _cycling_selection := false
var _projectile_visuals: ProjectileVisuals
var _artillery_preview: ArtilleryPreview
var _artillery_distance: Label
var _battle_hud: BattleHUD
var _hud_dirty := true
var _control_groups := BattleControlGroups.new()
var _menu: Control
var _task_overlay: TaskQueueOverlay
var _menu_page := "home"
var _combat_overview: Dictionary = {}
var _has_combat_overview := false
var _combat_records_tab := "kills"

@onready var _units: Node3D = $Units
@onready var _camera: Camera3D = $Units/Camera3D


func _ready() -> void:
	if not replay_mode and NetworkManager.acceptance_06c and "--server" not in OS.get_cmdline_user_args():
		if "--acceptance-controls" in OS.get_cmdline_user_args():
			var acceptance_controls := Acceptance06CControls.new()
			acceptance_controls.owned_selection = func(): return _command_unit_ids(MovementSimulation.MoveMode.BASIC)
			if NetworkManager.acceptance_full_06:
				acceptance_controls.structure_lookup = func(id): return NetworkManager.presentation.live_structures.get(id,{})
			add_child(acceptance_controls)
		if NetworkManager.acceptance_full_06:
			var explosions := TemporaryExplosionVisual.new()
			add_child(explosions)
			NetworkManager.acceptance_explosion_received.connect(explosions.show_event)
			NetworkManager.presentation.reset_received.connect(explosions.clear)
	if presentation_source == null:
		presentation_source = PresentationFeed.new() if replay_mode else NetworkManager.presentation
	if not replay_mode and "--server" not in OS.get_cmdline_user_args() and "--test-role=server" not in OS.get_cmdline_user_args():
		_projectile_visuals = ProjectileVisuals.new()
		_projectile_visuals.setup(presentation_source)
		add_child(_projectile_visuals)
	presentation_source.reset_received.connect(_reset_replicated_units)
	_camera.rotation_started.connect(_on_camera_rotation_started)
	presentation_source.unit_spawn_received.connect(_on_unit_spawn_received)
	presentation_source.unit_positions_received.connect(_on_unit_positions_received)
	presentation_source.unit_move_targets_received.connect(_on_unit_move_targets_received)
	presentation_source.unit_move_paths_received.connect(_on_unit_move_paths_received)
	presentation_source.unit_move_modes_received.connect(func(ids: Array[int], modes: Array[int]):
		for index: int in ids.size():
			if not _visual_units.has(ids[index]) or _visual_units[ids[index]].owner_peer_id != _view_owner_id(): continue
			_path_modes[ids[index]] = modes[index]
			if _movement_paths.has(ids[index]): _movement_paths[ids[index]].set_move_mode(modes[index]))
	presentation_source.unit_combat_state_received.connect(_on_unit_combat_state_received)
	presentation_source.combat_shot_received.connect(_on_combat_shot_received)
	presentation_source.unit_death_received.connect(_on_unit_death_received)
	presentation_source.unit_stops_received.connect(_on_unit_stops_received)
	presentation_source.unit_armament_received.connect(func(id: int, armed: bool):
		if _visual_units.has(id):
			_visual_units[id].armed = armed
			_unit_markers[id].armed = armed
			_unit_markers[id].refresh())
	presentation_source.unit_type_received.connect(_on_unit_type_received)
	presentation_source.unit_orientations_received.connect(_on_unit_orientations_received)
	presentation_source.unit_identity_received.connect(_on_unit_identity_received)
	presentation_source.unit_member_count_received.connect(_on_unit_member_count_received)
	presentation_source.unit_status_received.connect(func(status: Dictionary):
		if not _unit_markers.has(int(status.unit_id)): return
		var marker: UnitMarker = _unit_markers[int(status.unit_id)]
		marker.apply_status(status))
	presentation_source.unit_structure_received.connect(func(structure: Dictionary):
		if not structure.has("personnel") or not _unit_markers.has(int(structure.unit_id)): return
		var marker: UnitMarker = _unit_markers[int(structure.unit_id)]
		marker.apply_status(UnitStatusProjection.project(structure,true)))
	if not replay_mode:
		multiplayer.server_disconnected.connect(_clear_selection)
		multiplayer.server_disconnected.connect(_clear_movement_paths)
		multiplayer.server_disconnected.connect(_reset_replicated_units)
		multiplayer.connected_to_server.connect(_reset_replicated_units)
	var overlay := CanvasLayer.new()
	add_child(overlay)
	_marker_layer = Control.new()
	_marker_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(_marker_layer)
	_selection_rectangle = SELECTION_RECTANGLE.new()
	overlay.add_child(_selection_rectangle)
	_movement_mode_hint = Label.new()
	_movement_mode_hint.text = "快速移动：右键下令，F 取消"
	_movement_mode_hint.position = Vector2(16, 16)
	_movement_mode_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_movement_mode_hint.hide()
	overlay.add_child(_movement_mode_hint)
	if not replay_mode:
		if _projectile_visuals != null:
			_artillery_preview = ArtilleryPreview.new()
			if NetworkManager.acceptance_06c:
				var fixture_paths: Array[String] = ["normal","top"]
				if NetworkManager.acceptance_full_06: fixture_paths.append_array(["suppression","modules","manual","mechanical"])
				for fixture_path: String in fixture_paths:
					var fixture: UnitDefinition = load("res://data/units/acceptance_06c_%s.tres" % fixture_path)
					for allocation: WeaponAllocation in fixture.weapon_allocations:
						_artillery_preview.test_definitions[allocation.definition.definition_id] = allocation.definition
			add_child(_artillery_preview)
			_artillery_distance = Label.new()
			_artillery_distance.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_artillery_distance.add_theme_color_override("font_color",Color.RED)
			_artillery_distance.add_theme_color_override("font_outline_color",Color.BLACK)
			_artillery_distance.add_theme_constant_override("outline_size",3)
			_artillery_distance.hide()
			overlay.add_child(_artillery_distance)
			NetworkManager.deployment_state_received.connect(func(_state): _refresh_player_colors())
		_deployment_ui = DeploymentUI.new()
		_deployment_ui.setup(_camera, _ground_at)
		_deployment_ui.input_ownership_changed.connect(func(active: bool):
			for marker: UnitMarker in _unit_markers.values():
				marker.mouse_filter = Control.MOUSE_FILTER_IGNORE if active else Control.MOUSE_FILTER_PASS
			if active:
				_cancel_drag()
				_cancel_right_drag()
				_cancel_fast_move()
				_cancel_attack_move()
				_cancel_reverse_move()
				_pending_actions.clear()
				set_physics_process(false))
		overlay.add_child(_deployment_ui)
		_task_overlay = TaskQueueOverlay.new()
		_task_overlay.camera = _camera
		_task_overlay.units = _visual_units
		overlay.add_child(_task_overlay)
		NetworkManager.task_queue_received.connect(func(_rows): _task_overlay.queues = NetworkManager.local_task_queues; _task_overlay.queue_redraw())
		NetworkManager.combat_statistics_received.connect(func(_statistics): _refresh_combat_statistics())
		if NetworkManager.has_signal("combat_overview_received"):
			NetworkManager.connect("combat_overview_received", _on_combat_overview_received)
		multiplayer.server_disconnected.connect(_clear_combat_overview)
		if "--server" not in OS.get_cmdline_user_args() and "--test-role=server" not in OS.get_cmdline_user_args():
			_battle_hud = BattleHUD.new()
			overlay.add_child(_battle_hud)
			_battle_hud.configure_map(Rect2(movement_config.minimum_xz, movement_config.maximum_xz - movement_config.minimum_xz))
			_battle_hud.command_requested.connect(_on_hud_command)
			_battle_hud.group_requested.connect(_on_hud_group)
			_battle_hud.unit_requested.connect(_focus_selection_unit)
			_battle_hud.locate_requested.connect(_locate_disclosed_unit)
			presentation_source.unit_structure_received.connect(func(_state): _hud_dirty = true)
			presentation_source.unit_positions_received.connect(func(_ids, _positions): _hud_dirty = true)
			presentation_source.unit_combat_state_received.connect(func(_id, _team, _max, _health): _hud_dirty = true)
			presentation_source.unit_identity_received.connect(func(_id, _player, _definition): _hud_dirty = true)
			presentation_source.unit_member_count_received.connect(func(_id, _count): _hud_dirty = true)
			_deployment_ui.external_messages = true
			_deployment_ui._message.hide()
			_deployment_ui.battlefield_notice.connect(func(text: String): _battle_hud.post_message(text))
			NetworkManager.command_notice_received.connect(func(notice: Dictionary):
				var names := {"move":"移动", "stop":"取消任务", "ground_fire":"强制开火", "artillery":"火炮"}
				_battle_hud.post_message("%s：%s" % [names.get(notice.command, "操作"), notice.reason], notice.unit_ids))
	get_window().focus_exited.connect(_cancel_drag)
	get_window().focus_exited.connect(_cancel_fast_move)
	get_window().focus_exited.connect(_cancel_attack_move)
	get_window().focus_exited.connect(_cancel_reverse_move)
	if not replay_mode:
		multiplayer.server_disconnected.connect(_cancel_reverse_move)
		multiplayer.server_disconnected.connect(_cancel_attack_move)
		multiplayer.server_disconnected.connect(_cancel_fast_move)
	_formation_preview = Node3D.new()
	add_child(_formation_preview)
	set_physics_process(false)


func _unhandled_input(event: InputEvent) -> void:
	if replay_mode:
		return
	if multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_handle_world_input(event)


func _handle_world_input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed and not event.echo:
		if _menu != null and _menu.visible:
			_close_menu()
		else:
			_open_menu()
		get_viewport().set_input_as_handled()
		return
	if _menu != null and _menu.visible:
		get_viewport().set_input_as_handled()
		return
	if _deployment_ui != null and not _camera.is_rotating() and _deployment_ui.handle_world_input(event):
		get_viewport().set_input_as_handled()
		return
	# Called only after connection/role checks; kept separate for offline input checks.
	if _camera.is_rotating():
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		if _handle_control_group_key(event):
			get_viewport().set_input_as_handled()
		elif event.keycode in [KEY_G,KEY_T] and event.pressed and not event.echo and not event.ctrl_pressed and not event.alt_pressed and not event.shift_pressed and get_viewport().gui_get_focus_owner() == null:
			_consume_move_mode()
			_fire_mode = "artillery" if event.keycode == KEY_T else "ground_fire"
			_movement_mode_hint.text = "T 单点一发：左键选择落点，E 退出" if _fire_mode == "artillery" else "G 强制地面开火：左键选择位置，E 退出"
			_movement_mode_hint.show()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_TAB and event.pressed and not event.echo and get_viewport().gui_get_focus_owner() == null:
			_cycle_marker_selection(event.shift_pressed)
			get_viewport().set_input_as_handled()
		elif _is_reverse_move_key(event):
			_arm_reverse_move()
			get_viewport().set_input_as_handled()
		elif _is_attack_move_key(event):
			_arm_attack_move()
			get_viewport().set_input_as_handled()
		elif _is_fast_move_key(event):
			_toggle_fast_move()
			get_viewport().set_input_as_handled()
		elif _is_stop_key(event):
			if not _fire_mode.is_empty() or _attack_move_armed or _fast_move_armed or _reverse_move_armed or _right_pressed or _left_pressed or _box_dragging:
				_consume_move_mode()
				_cancel_right_drag()
				_cancel_drag()
			else:
				_pending_actions.clear()
				_queue_action({"type": "stop"})
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _right_pressed:
		_right_dragging = _right_dragging or event.position.distance_to(_right_start) > DRAG_THRESHOLD
		_update_formation_preview(event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _left_pressed:
		_update_drag(event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		if get_viewport().gui_get_focus_owner() != null:
			_cancel_right_drag()
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if not _fire_mode.is_empty():
				if event.pressed: _confirm_fire(event.position,event.shift_pressed)
				get_viewport().set_input_as_handled()
				return
			if _attack_move_armed or _fast_move_armed or _reverse_move_armed or _right_pressed:
				_consume_move_mode()
				_cancel_right_drag()
				_cancel_drag()
				get_viewport().set_input_as_handled()
				return
			if event.pressed:
				_cancel_right_drag()
				_left_pressed = true
				_box_dragging = false
				_drag_start = event.position
				_drag_shift = event.shift_pressed
			elif _left_pressed:
				_update_drag(event.position)
				if _box_dragging:
					_queue_action({"type": "box", "rectangle": Rect2(_drag_start, event.position - _drag_start).abs(),"shift":_drag_shift})
				else:
					_queue_action({"type": "click", "position": event.position,"shift":_drag_shift})
				_cancel_drag()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT and not _left_pressed:
			if not _fire_mode.is_empty():
				get_viewport().set_input_as_handled()
				return
			if event.pressed:
				_right_pressed = true
				_right_start = event.position
				_right_ground = _ground_at(event.position)
				_right_dragging = false
				_right_mode = _current_move_mode()
			elif _right_pressed:
				_right_dragging = _right_dragging or event.position.distance_to(_right_start) > DRAG_THRESHOLD
				_queue_action({"type": "move", "position": _right_start if _right_dragging else event.position, "end": event.position, "dragged": _right_dragging, "mode": _right_mode,
					"ground": _right_ground if _right_dragging else _ground_at(event.position), "tip": _ground_at(event.position),"append":event.shift_pressed})
				_consume_move_mode()
				_cancel_right_drag()
			get_viewport().set_input_as_handled()



func _open_menu() -> void:
	# Presentation-only menu; never pauses server simulation.
	if _menu == null:
		_build_game_menu()
	if _deployment_ui != null:
		_deployment_ui.set_process_input(false)
	_cancel_drag()
	_cancel_right_drag()
	_pending_actions.clear()
	set_physics_process(false)
	_camera.cancel_controls()
	_camera.input_blocked = true
	_menu.show()
	_show_menu_page("home")


func _build_game_menu() -> void:
	_menu = Control.new()
	_menu.name = "GameMenu"
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu.z_index = 100
	_selection_rectangle.get_parent().add_child(_menu)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.68)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu.add_child(backdrop)
	var center := CenterContainer.new()
	center.name = "MenuCenter"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	_menu.add_child(center)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	center.add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	panel.add_child(outer)
	var header := HBoxContainer.new()
	outer.add_child(header)
	var title := Label.new()
	title.name = "MenuTitle"
	title.text = "游戏菜单"
	title.add_theme_font_size_override("font_size", 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var back := Button.new()
	back.name = "MenuBack"
	back.text = "返回菜单"
	back.pressed.connect(func(): _show_menu_page("home"))
	header.add_child(back)
	var page_area := Control.new()
	page_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(page_area)
	var home := ScrollContainer.new()
	home.name = "MenuHome"
	home.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	home.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page_area.add_child(home)
	var home_box := VBoxContainer.new()
	home_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	home_box.add_theme_constant_override("separation", 12)
	home.add_child(home_box)
	for entry: Array in [["OutOfMatchSettingsPage", "局外设置"], ["CombatStatisticsPage", "KD"], ["CombatRecordsPage", "击杀记录"]]:
		var button := Button.new()
		button.name = str(entry[0])
		button.text = str(entry[1])
		button.custom_minimum_size.y = 54
		button.pressed.connect(_show_menu_page.bind(str(entry[0])))
		home_box.add_child(button)
	var settings_scroll := _new_menu_page(page_area, "OutOfMatchSettings")
	var settings := VBoxContainer.new()
	settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_scroll.add_child(settings)
	var settings_title := Label.new()
	settings_title.text = "出生后移动方式"
	settings.add_child(settings_title)
	var spawn_mode := OptionButton.new()
	spawn_mode.name = "SpawnMoveMode"
	spawn_mode.add_item("常规移动", MovementSimulation.MoveMode.BASIC)
	spawn_mode.add_item("快速移动", MovementSimulation.MoveMode.FAST)
	spawn_mode.select(1 if _deployment_ui.spawn_move_mode == MovementSimulation.MoveMode.FAST else 0)
	spawn_mode.item_selected.connect(func(_index: int): _deployment_ui.spawn_move_mode = spawn_mode.get_selected_id())
	settings.add_child(spawn_mode)
	var stats_scroll := _new_menu_page(page_area, "CombatStatisticsPageContent")
	var stats_box := VBoxContainer.new()
	stats_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_scroll.add_child(stats_box)
	var stats_label := Label.new()
	stats_label.name = "CombatStatistics"
	stats_box.add_child(stats_label)
	var table := GridContainer.new()
	table.name = "CombatStatisticsTable"
	table.columns = 5
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_box.add_child(table)
	stats_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	var records_scroll := _new_menu_page(page_area, "CombatRecordsPageContent")
	var records_box := VBoxContainer.new()
	records_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	records_scroll.add_child(records_box)
	var tabs := HBoxContainer.new()
	records_box.add_child(tabs)
	var records_group := ButtonGroup.new()
	var kills_tab := Button.new()
	kills_tab.name = "MyUnitKills"
	kills_tab.text = "我的单位击杀"
	kills_tab.toggle_mode = true
	kills_tab.button_group = records_group
	kills_tab.button_pressed = true
	kills_tab.pressed.connect(func(): _combat_records_tab = "kills"; _refresh_combat_statistics())
	tabs.add_child(kills_tab)
	var deaths_tab := Button.new()
	deaths_tab.name = "MyUnitDeaths"
	deaths_tab.text = "我的单位被击杀"
	deaths_tab.toggle_mode = true
	deaths_tab.button_group = records_group
	deaths_tab.pressed.connect(func(): _combat_records_tab = "deaths"; _refresh_combat_statistics())
	tabs.add_child(deaths_tab)
	var records := VBoxContainer.new()
	records.name = "CombatRecords"
	records.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	records_box.add_child(records)
	var footer := HBoxContainer.new()
	footer.name = "MenuFooter"
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.mouse_filter = Control.MOUSE_FILTER_PASS
	_menu.add_child(footer)
	var resume := Button.new()
	resume.name = "ResumeGame"
	resume.text = "返回游戏"
	resume.pressed.connect(func(): _close_menu(); resume.release_focus())
	footer.add_child(resume)
	get_viewport().size_changed.connect(_resize_game_menu_panel.bind(panel, center, footer, resume))
	_resize_game_menu_panel(panel, center, footer, resume)
	_menu.hide()


func _resize_game_menu_panel(panel: PanelContainer, center: CenterContainer, footer: HBoxContainer, resume: Button) -> void:
	if not is_instance_valid(panel) or not is_instance_valid(center) or not is_instance_valid(footer) or not is_instance_valid(resume): return
	var viewport_size := get_viewport().get_visible_rect().size
	var side_margin := minf(16.0, viewport_size.x * 0.04)
	var top_margin := minf(16.0, viewport_size.y * 0.04)
	var bottom_margin := minf(24.0, viewport_size.y * 0.06)
	var panel_footer_gap := minf(16.0, viewport_size.y * 0.04)
	var button_width := maxf(1.0, minf(340.0, viewport_size.x - side_margin * 2.0))
	var button_height := maxf(1.0, minf(64.0, viewport_size.y - top_margin - bottom_margin))
	resume.custom_minimum_size = Vector2(button_width, button_height)
	resume.add_theme_font_size_override("font_size", 24 if button_width >= 280.0 else 18)
	footer.offset_left = side_margin
	footer.offset_right = -side_margin
	footer.offset_top = -bottom_margin - button_height
	footer.offset_bottom = -bottom_margin
	center.offset_top = top_margin
	center.offset_bottom = -(button_height + bottom_margin + panel_footer_gap)
	var available := Vector2(maxf(1.0, viewport_size.x - side_margin * 2.0), maxf(1.0, viewport_size.y - top_margin - button_height - bottom_margin - panel_footer_gap))
	panel.custom_minimum_size = Vector2(minf(900.0, available.x), minf(640.0, available.y))
	panel.size = panel.custom_minimum_size


func _new_menu_page(parent: Control, page_name: String) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = page_name
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.hide()
	parent.add_child(scroll)
	return scroll


func _show_menu_page(page_name: String) -> void:
	_menu_page = page_name
	var title := _menu.find_child("MenuTitle", true, false) as Label
	var back := _menu.find_child("MenuBack", true, false) as Button
	var home := _menu.find_child("MenuHome", true, false) as Control
	var settings := _menu.find_child("OutOfMatchSettings", true, false) as Control
	var stats := _menu.find_child("CombatStatisticsPageContent", true, false) as Control
	var records := _menu.find_child("CombatRecordsPageContent", true, false) as Control
	home.visible = page_name == "home"
	settings.visible = page_name == "OutOfMatchSettingsPage"
	stats.visible = page_name == "CombatStatisticsPage"
	records.visible = page_name == "CombatRecordsPage"
	back.visible = page_name != "home"
	match page_name:
		"OutOfMatchSettingsPage": title.text = "局外设置"
		"CombatStatisticsPage": title.text = "KD"
		"CombatRecordsPage": title.text = "击杀记录"
		_: title.text = "游戏菜单"
	_refresh_combat_statistics()


func _close_menu() -> void:
	var focus_owner := get_viewport().gui_get_focus_owner()
	if _menu != null and is_instance_valid(focus_owner) and _menu.is_ancestor_of(focus_owner):
		focus_owner.release_focus()
	if _menu != null: _menu.hide()
	if _deployment_ui != null:
		_deployment_ui.set_process_input(true)
	_camera.input_blocked = false


func _refresh_combat_statistics() -> void:
	if _menu == null: return
	var label := _menu.find_child("CombatStatistics",true,false) as Label
	if label != null:
		var statistics := _viewer_combat_player()
		if statistics.is_empty() and not _has_combat_overview: statistics = NetworkManager.local_combat_statistics
		if statistics.is_empty():
			label.text = "价值统计：等待服务器"
		else:
			var kd_text := _combat_kd_text(statistics)
			var death_value: Variant = statistics.get("death_value")
			label.text = "本机 · 击杀价值 %s · 死亡价值 %s · 价值KD %s" % [_combat_value_text(statistics.get("kill_value")),_combat_value_text(death_value),kd_text]
	_refresh_combat_statistics_table()
	_refresh_combat_records()


func _refresh_combat_statistics_table() -> void:
	var table := _menu.find_child("CombatStatisticsTable", true, false) as GridContainer
	if table == null: return
	for child: Node in table.get_children():
		table.remove_child(child)
		child.queue_free()
	for heading: String in ["玩家", "击杀价值", "死亡价值", "价值KD", "状态"]:
		var heading_label := Label.new()
		heading_label.text = heading
		table.add_child(heading_label)
	var rows: Array[Dictionary] = []
	if _has_combat_overview:
		for raw: Variant in _combat_overview.get("players", []):
			if raw is Dictionary: rows.append(raw)
		rows.sort_custom(func(a: Dictionary, b: Dictionary): return int(_overview_player(a).get("player_id", 0)) < int(_overview_player(b).get("player_id", 0)))
	else:
		var legacy: Dictionary = NetworkManager.local_combat_statistics
		if not legacy.is_empty():
			rows.append({"player_id": NetworkManager.local_player_id, "label": "我", "connected": true,
				"kill_value": legacy.get("kill_value"), "death_value": legacy.get("death_value"),
				"value_kd": legacy.get("value_kd"), "configured": legacy.get("configured", false),
				"display_kd": legacy.get("display_kd", "未配置")})
	if rows.is_empty():
		var empty := Label.new()
		empty.text = "等待服务器统计"
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		table.add_child(empty)
		for _column: int in 4: table.add_child(Control.new())
		return
	var viewer_id := int(_combat_overview.get("viewer_player_id", NetworkManager.local_player_id)) if _has_combat_overview else NetworkManager.local_player_id
	for row: Dictionary in rows:
		var player := _overview_player(row)
		var player_id := int(player.get("player_id", 0))
		var name_label := Label.new()
		name_label.text = str(row.get("label", "玩家 %d" % player_id)) + ("（我）" if player_id == viewer_id else "")
		table.add_child(name_label)
		for field: String in ["kill_value", "death_value"]:
			var value_label := Label.new()
			value_label.text = _combat_value_text(player.get(field))
			table.add_child(value_label)
		var kd_label := Label.new()
		kd_label.text = _combat_kd_text(player)
		table.add_child(kd_label)
		var status := Label.new()
		status.text = "在线" if bool(row.get("connected", true)) else "掉线"
		table.add_child(status)


func _combat_kd_text(player: Dictionary) -> String:
	var display_kd: Variant = player.get("display_kd")
	var kill_value: Variant = player.get("kill_value")
	var death_value: Variant = player.get("death_value")
	if display_kd != null and str(display_kd) == "未配置": return "未配置"
	if kill_value == null or death_value == null: return "未配置"
	if player.has("configured") and not bool(player.configured): return "未配置"
	if float(death_value) == 0.0: return "无损"
	if display_kd != null: return str(display_kd)
	var value_kd: Variant = player.get("value_kd")
	return str(value_kd) if value_kd != null else "未配置"


func _overview_player(row: Dictionary) -> Dictionary:
	var project_player: Variant = row.get("project_player", row)
	return project_player if project_player is Dictionary else row


func _viewer_combat_player() -> Dictionary:
	if not _has_combat_overview: return {}
	var viewer_id := int(_combat_overview.get("viewer_player_id", NetworkManager.local_player_id))
	for raw: Variant in _combat_overview.get("players", []):
		if not raw is Dictionary: continue
		var player := _overview_player(raw)
		if int(player.get("player_id", -1)) == viewer_id: return player
	return {}


func _refresh_combat_records() -> void:
	var container := _menu.find_child("CombatRecords", true, false) as VBoxContainer
	if container == null: return
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()
	var viewer_id := int(_combat_overview.get("viewer_player_id", NetworkManager.local_player_id))
	var records: Array[Dictionary] = []
	if _has_combat_overview:
		for raw: Variant in _combat_overview.get("records", []):
			if raw is Dictionary:
				var belongs := int(raw.get("killer_player_id", -1)) == viewer_id if _combat_records_tab == "kills" else int(raw.get("player_id", -1)) == viewer_id
				if belongs: records.append(raw)
	records.sort_custom(func(a: Dictionary, b: Dictionary):
		if a.has("sequence") and b.has("sequence"): return int(a.sequence) > int(b.sequence)
		return float(a.get("time_seconds", 0.0)) > float(b.get("time_seconds", 0.0)))
	if records.is_empty():
		var empty := Label.new()
		empty.text = "暂无单位击杀记录" if _combat_records_tab == "kills" else "暂无单位被击杀记录"
		container.add_child(empty)
		return
	for record: Dictionary in records:
		var line := Label.new()
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var time_text := _combat_record_time(float(record.get("time_seconds", 0.0)))
		var killer_id := int(record.get("killer_unit_id", 0))
		var victim_id := int(record.get("unit_id", 0))
		var killer_player := int(record.get("killer_player_id", 0))
		var victim_player := int(record.get("player_id", 0))
		var marker := "（自伤）" if killer_id == victim_id else ("（友伤）" if bool(record.get("friendly_fire", false)) else "")
		line.text = "%s  来源：单位#%d·%s·%s → 被击杀：单位#%d·%s·%s  价值：%s%s" % [time_text, killer_id, _unit_kind_text(int(record.get("killer_unit_kind", -1))), _combat_player_label(killer_player), victim_id, _unit_kind_text(int(record.get("unit_kind", -1))), _combat_player_label(victim_player), _combat_value_text(record.get("value_points")), marker]
		container.add_child(line)


func _combat_record_time(seconds: float) -> String:
	var elapsed := maxi(0, int(floor(seconds)))
	return "%02d:%02d" % [elapsed / 60, elapsed % 60]


func _combat_player_label(player_id: int) -> String:
	if player_id <= 0: return "非玩家"
	for raw: Variant in _combat_overview.get("players", []):
		if not raw is Dictionary: continue
		var player := _overview_player(raw)
		if int(player.get("player_id", -1)) == player_id: return str(raw.get("label", "玩家 %d" % player_id))
	return "未知玩家"


func _unit_kind_text(unit_kind: int) -> String:
	return "步兵" if unit_kind == UnitDefinition.UnitType.INFANTRY else ("装甲车辆" if unit_kind == UnitDefinition.UnitType.ARMORED_VEHICLE else "未知单位")


func _on_combat_overview_received(overview: Dictionary) -> void:
	_combat_overview = overview.duplicate(true)
	_has_combat_overview = true
	_refresh_combat_statistics()


func _clear_combat_overview() -> void:
	_combat_overview.clear()
	_has_combat_overview = false
	_refresh_combat_statistics()

func _combat_value_text(value: Variant) -> String:
	return "未配置" if value == null else str(value)

func _confirm_fire(position: Vector2,append: bool = false) -> void:
	_queue_action({"type":_fire_mode,"position":_ground_at(position),"append":append})
	_consume_move_mode()
	_cancel_drag()

func _update_drag(position: Vector2) -> void:
	if position.distance_to(_drag_start) > DRAG_THRESHOLD:
		_box_dragging = true
	if _box_dragging:
		_selection_rectangle.show_rectangle(Rect2(_drag_start, position - _drag_start).abs())


func _is_stop_key(event: InputEventKey) -> bool:
	return event.keycode == KEY_E and event.pressed and not event.echo \
		and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed \
		and get_viewport().gui_get_focus_owner() == null


func _on_camera_rotation_started() -> void:
	_cancel_drag()
	_pending_actions.clear()
	set_physics_process(false)


func _is_fast_move_key(event: InputEventKey) -> bool:
	return event.keycode == KEY_F and event.pressed and not event.echo \
		and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed \
		and get_viewport().gui_get_focus_owner() == null


func _toggle_fast_move() -> void:
	_fire_mode = ""
	_cancel_right_drag()
	_cancel_attack_move()
	_cancel_reverse_move()
	_fast_move_armed = not _fast_move_armed
	_movement_mode_hint.text = "快速移动：右键下令，F 取消"
	_movement_mode_hint.visible = _fast_move_armed


func _cancel_fast_move() -> void:
	_fast_move_armed = false
	_movement_mode_hint.hide()


func _current_move_mode() -> int:
	var mode := MovementSimulation.MoveMode.FAST if _fast_move_armed else MovementSimulation.MoveMode.BASIC
	if _attack_move_armed:
		mode = MovementSimulation.MoveMode.ATTACK
	if _reverse_move_armed:
		mode = MovementSimulation.MoveMode.REVERSE
	return mode


func _consume_move_mode() -> int:
	_fire_mode = ""
	var mode := _current_move_mode()
	_cancel_attack_move()
	_cancel_fast_move()
	_cancel_reverse_move()
	return mode


func _is_attack_move_key(event: InputEventKey) -> bool:
	return event.keycode == KEY_Q and event.pressed and not event.echo \
		and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed \
		and get_viewport().gui_get_focus_owner() == null


func _cancel_attack_move() -> void:
	_attack_move_armed = false
	if not _fast_move_armed:
		_movement_mode_hint.hide()


func _arm_attack_move() -> void:
	_fire_mode = ""
	_cancel_fast_move()
	_cancel_reverse_move()
	_cancel_drag()
	_attack_move_armed = true
	_movement_mode_hint.text = "攻击移动：右键下令，E 或左键退出"
	_movement_mode_hint.show()


func _is_reverse_move_key(event: InputEventKey) -> bool:
	return event.keycode == KEY_R and event.pressed and not event.echo \
		and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed \
		and get_viewport().gui_get_focus_owner() == null


func _arm_reverse_move() -> void:
	_fire_mode = ""
	_cancel_fast_move()
	_cancel_attack_move()
	_cancel_drag()
	_reverse_move_armed = true
	_movement_mode_hint.text = "倒车：右键下令，E 或左键退出"
	_movement_mode_hint.show()


func _cancel_reverse_move() -> void:
	_fire_mode = ""
	_clear_artillery_preview()
	_reverse_move_armed = false
	if not _fast_move_armed and not _attack_move_armed:
		_movement_mode_hint.hide()


func _on_unit_orientations_received(unit_ids: Array[int], yaws: Array[float]) -> void:
	for index: int in unit_ids.size():
		if _visual_units.has(unit_ids[index]):
			_visual_units[unit_ids[index]].display_yaw(yaws[index])


func _cancel_drag() -> void:
	_cancel_right_drag()
	_left_pressed = false
	_box_dragging = false
	_selection_rectangle.hide()


func _queue_action(action: Dictionary) -> void:
	_pending_actions.append(action)
	set_physics_process(true)


func _physics_process(_delta: float) -> void:
	# Query physics in its tick, and do no per-frame picking when idle.
	for action: Dictionary in _pending_actions:
		match action["type"]:
			"click":
				_select_unit(_pick_unit(action["position"]),action.get("shift",false))
			"box":
				_select_box(action["rectangle"],action.get("shift",false))
			"move":
				_request_move_at(action["position"], action.get("mode", MovementSimulation.MoveMode.BASIC), action.get("end", action["position"]), action.get("dragged", false), action.get("ground"), action.get("tip"),action.get("append",false))
			"stop":
				_request_stop_selected()
			"ground_fire", "artillery":
				if action.position is Vector3 and not replay_mode:
					NetworkManager.request_ground_fire(_command_unit_ids(MovementSimulation.MoveMode.BASIC),action.position,action.type == "artillery",1 if action.type == "artillery" else -1,action.get("append",false))
	_pending_actions.clear()
	set_physics_process(false)


func _pick_unit(screen_position: Vector2) -> Node3D:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var origin := camera.project_ray_origin(screen_position)
	var end := origin + camera.project_ray_normal(screen_position) * PICK_DISTANCE
	var query := PhysicsRayQueryParameters3D.create(origin, end, UNIT_PICK_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var unit := (hit["collider"] as Node).get_parent() as Node3D
	if unit == null or not _visual_units.values().has(unit) or unit.is_queued_for_deletion():
		return null
	return unit


func _select_unit(unit: Node3D, shift: bool = false) -> void:
	# Ownership is read from the server-provided visual metadata, never changed.
	if unit != null and unit.owner_peer_id != _view_owner_id():
		return
	var selection: Dictionary[int, Node3D] = {}
	if shift: selection = _selection_collection.duplicate()
	if unit != null:
		if shift and selection.has(unit.unit_id): selection.erase(unit.unit_id)
		else: selection[unit.unit_id] = unit
	_replace_selection(selection)


func _select_box(rectangle: Rect2, shift: bool = false) -> void:
	var selection: Dictionary[int, Node3D] = {}
	if shift: selection = _selection_collection.duplicate()
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		for unit_id: int in _visual_units:
			var unit := _visual_units[unit_id]
			if not is_instance_valid(unit) or unit.is_queued_for_deletion():
				continue
			if unit.owner_peer_id != _view_owner_id():
				continue
			if camera.is_position_behind(unit.global_position):
				continue
			if rectangle.has_point(camera.unproject_position(unit.global_position)):
				selection[unit_id] = unit
	_replace_selection(selection)


func _replace_selection(selection: Dictionary[int, Node3D]) -> void:
	_hud_dirty = true
	for unit: Node3D in _selected_units.values():
		if is_instance_valid(unit):
			unit.set_selected(false)
	_selected_units = selection
	if not _cycling_selection: _selection_collection = selection.duplicate()
	for unit: Node3D in _selected_units.values():
		unit.set_selected(true)
	for id: int in _unit_markers:
		_unit_markers[id].selected = _selected_units.has(id)
		_unit_markers[id].refresh()
	if not replay_mode:
		for id: int in _movement_paths: _movement_paths[id].visible = _selected_units.has(id)


func _prune_selection() -> void:
	for unit_id: int in _selected_units.keys():
		var unit := _selected_units[unit_id]
		if not is_instance_valid(unit) or not unit.is_inside_tree() or unit.is_queued_for_deletion():
			_selected_units.erase(unit_id)


func _clear_selection() -> void:
	_pending_actions.clear()
	_cancel_drag()
	set_physics_process(false)
	_select_unit(null)


func _reset_replicated_units() -> void:
	if not replay_mode: NetworkManager.local_task_queues.clear()
	if _menu != null and _menu.visible: _close_menu()
	elif _deployment_ui != null: _deployment_ui.set_process_input(true)
	_clear_combat_overview()
	_refresh_combat_statistics()
	if _task_overlay != null:
		_task_overlay.selection.clear()
		_task_overlay.queues.clear()
		_task_overlay.queue_redraw()
	_control_groups.clear()
	if _battle_hud != null: _battle_hud.clear_session()
	_hud_dirty = true
	if _projectile_visuals != null: _projectile_visuals.clear()
	# A connection starts with a complete live snapshot, never the previous session's visuals.
	_clear_selection()
	_clear_movement_paths()
	for id: int in _visual_units:
		var unit := _visual_units[id]
		var removed := _on_visual_unit_removed.bind(id)
		if unit.tree_exiting.is_connected(removed):
			unit.tree_exiting.disconnect(removed)
		unit.hide()
		unit.queue_free()
	_visual_units.clear()
	_dead_units.clear()
	for marker: UnitMarker in _unit_markers.values():
		marker.hide()
		marker.queue_free()
	_unit_markers.clear()
	_selection_collection.clear()


func _on_unit_spawn_received(unit_id: int, owner_peer_id: int, position: Vector3) -> void:
	if _visual_units.has(unit_id) or _dead_units.has(unit_id):
		return

	var unit := UNIT_SCENE.instantiate() as Node3D
	unit.legacy_model_binding = replay_mode
	unit.name = "Unit_%d" % unit_id
	unit.setup(unit_id, owner_peer_id)
	unit.position = position
	_units.add_child(unit)
	_visual_units[unit_id] = unit
	var marker := UnitMarker.new()
	marker.chosen.connect(_choose_marker.bind(unit_id))
	_marker_layer.add_child(marker)
	if _deployment_ui != null and _deployment_ui.owns_commands(): marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_unit_markers[unit_id] = marker
	unit.tree_exiting.connect(_on_visual_unit_removed.bind(unit_id))


func _on_unit_combat_state_received(unit_id: int, team_id: int, maximum_health: float, health: float) -> void:
	# Live authoritative zero-HP snapshots retire presentation immediately.
	# Server identity/audit lifetime and frozen replay death events stay separate.
	if not replay_mode and health <= 0.0:
		_on_unit_death_received(unit_id)
		return
	if _visual_units.has(unit_id):
		_visual_units[unit_id].display_combat_state(team_id, maximum_health, health)
		_unit_markers[unit_id].team_id = team_id
		if not replay_mode:
			_unit_markers[unit_id].apply_health(health,maximum_health)
		_unit_markers[unit_id].refresh()
		if not replay_mode and NetworkManager.acceptance_06c and "--acceptance-controls" in OS.get_cmdline_user_args():
			_unit_markers[unit_id].tooltip_text = "TEST ONLY #%d team=%d HP=%.3f/%.3f" % [unit_id,team_id,health,maximum_health]
		else:
			_unit_markers[unit_id].tooltip_text = ""
		_refresh_player_colors()


func _on_unit_type_received(unit_id: int, unit_type: int) -> void:
	if _visual_units.has(unit_id):
		_visual_units[unit_id].display_unit_type(unit_type)
		_unit_markers[unit_id].unit_kind = unit_type
		_unit_markers[unit_id].refresh()

func _on_unit_identity_received(id: int, player: int, definition: String) -> void:
	if not _visual_units.has(id): return
	_visual_units[id].owner_player_id = player
	_visual_units[id].definition_id = definition
	_unit_markers[id].player_id = player
	if not replay_mode: _unit_markers[id].temporary_role = TemporaryUnitBadge.role_for(definition)
	_unit_markers[id].refresh()
	_refresh_player_colors()

func _refresh_player_colors() -> void:
	if replay_mode: return
	for id: int in _visual_units:
		var unit: Node3D = _visual_units[id]
		var marker: UnitMarker = _unit_markers[id]
		marker.viewer_player_id = NetworkManager.local_player_id
		unit.display_owner_color(marker.style.color_for(unit.owner_player_id,marker.viewer_player_id))
		marker.refresh()

func _clear_artillery_preview() -> void:
	if _artillery_preview != null: _artillery_preview.clear()
	if _artillery_distance != null: _artillery_distance.hide()

func _update_artillery_preview(position: Vector2) -> void:
	if replay_mode or _fire_mode.is_empty() or _camera.is_rotating():
		_clear_artillery_preview()
		return
	var point: Variant = _ground_at(position)
	if not point is Vector3 or not point.is_finite(): _clear_artillery_preview(); return
	var structures: Array[Dictionary] = []
	for id: int in _selected_units:
		if _selected_units[id].owner_player_id != NetworkManager.local_player_id or NetworkManager.local_player_id <= 0: continue
		if presentation_source.live_structures.has(id): structures.append(presentation_source.live_structures[id])
	_artillery_distance.text = _artillery_preview.show_targets(structures,point,_fire_mode == "artillery")
	_artillery_distance.position = position+Vector2(16,20)
	_artillery_distance.show()

func _on_unit_member_count_received(id: int,count: int) -> void:
	if _unit_markers.has(id):
		_unit_markers[id].member_count = count
		_unit_markers[id].refresh()

func _process(_delta: float) -> void:
	if _task_overlay != null:
		if _task_overlay.selection != _selected_units.keys():
			_task_overlay.selection.assign(_selected_units.keys())
			_task_overlay.queue_redraw()
	if _battle_hud != null and _hud_dirty:
		_refresh_hud()
	if _artillery_preview != null: _update_artillery_preview(get_viewport().get_mouse_position())
	for id: int in _unit_markers:
		var unit := _visual_units[id]
		_unit_markers[id].project(_camera,unit.global_position,1.0 if replay_mode else _camera.marker_scale())
		_unit_markers[id].visible = _unit_markers[id].visible and unit.is_visible_in_tree()

func _choose_marker(shift: bool,double_click: bool,id: int) -> void:
	if _menu != null and _menu.visible: return
	if replay_mode or _camera.is_rotating() or (_deployment_ui != null and _deployment_ui.owns_commands()): return
	if not _fire_mode.is_empty():
		_confirm_fire(get_viewport().get_mouse_position())
		return
	if _fast_move_armed or _attack_move_armed or _reverse_move_armed:
		_cancel_fast_move()
		_cancel_attack_move()
		_cancel_reverse_move()
		return
	var unit: Node3D = _visual_units.get(id)
	if unit == null or unit.owner_peer_id != _view_owner_id(): return
	if double_click:
		var selection: Dictionary[int,Node3D] = {}
		for candidate: Node3D in _visual_units.values():
			if candidate.owner_peer_id != _view_owner_id() or candidate.health <= 0 or candidate.definition_id != unit.definition_id or candidate.unit_type != unit.unit_type or candidate.armed != unit.armed: continue
			if not _camera.is_position_behind(candidate.global_position) and get_viewport().get_visible_rect().has_point(_camera.unproject_position(candidate.global_position)): selection[candidate.unit_id] = candidate
		_replace_selection(selection)
	elif shift:
		var selection := _selection_collection.duplicate()
		if selection.has(id): selection.erase(id)
		else: selection[id] = unit
		_replace_selection(selection)
	else:
		if not _selection_collection.has(id): _selection_collection = {id:unit}
		_cycling_selection = true
		var selection: Dictionary[int,Node3D] = {id:unit}
		_replace_selection(selection)
		_cycling_selection = false

func _cycle_marker_selection(restore: bool) -> void:
	var ids := _ordered_selection_ids()
	if ids.is_empty(): return
	_cycling_selection = true
	if restore: _replace_selection(_selection_collection.duplicate())
	else:
		var current: int = _selected_units.keys()[0] if _selected_units.size() == 1 else -1
		var next: int = ids[(ids.find(current)+1)%ids.size()]
		var selection: Dictionary[int,Node3D] = {next:_selection_collection[next]}
		_replace_selection(selection)
	_cycling_selection = false

func _ordered_selection_ids() -> Array[int]:
	if replay_mode:
		var legacy_ids: Array[int] = []
		legacy_ids.assign(_selection_collection.keys())
		legacy_ids.sort_custom(func(a: int,b: int):
			var ua := _selection_collection[a]
			var ub := _selection_collection[b]
			if ua.unit_type != ub.unit_type: return ua.unit_type < ub.unit_type
			if ua.definition_id != ub.definition_id: return ua.definition_id < ub.definition_id
			return a < b)
		return legacy_ids
	var rows: Array[Dictionary] = []
	for id: int in _selection_collection:
		if _visual_units.has(id): rows.append(_hud_unit(id))
	return BattleHUDModel.selection_order(rows)

func _focus_selection_unit(id: int) -> void:
	if not _selection_collection.has(id) or (_menu != null and _menu.visible): return
	if not _fire_mode.is_empty() or _fast_move_armed or _attack_move_armed or _reverse_move_armed or (_deployment_ui != null and _deployment_ui.owns_commands()): return
	_cycling_selection = true
	var focused: Dictionary[int, Node3D] = {id:_selection_collection[id]}
	_replace_selection(focused)
	_cycling_selection = false


func _on_combat_shot_received(start: Vector3, end: Vector3) -> void:
	var visual := SHOT_VISUAL.new() as MeshInstance3D
	add_child(visual)
	visual.show_shot(_units.transform * start, _units.transform * end)


func _on_unit_death_received(unit_id: int) -> void:
	_dead_units[unit_id] = true
	var unit: Node3D = _visual_units.get(unit_id)
	_on_visual_unit_removed(unit_id)
	if is_instance_valid(unit):
		unit.hide()
		unit.queue_free()


func _on_visual_unit_removed(unit_id: int) -> void:
	_control_groups.remove_unit(unit_id)
	_hud_dirty = true
	var focused := _selected_units.size() == 1 and _selected_units.has(unit_id)
	_clear_unit_path(unit_id)
	if _task_overlay != null:
		_task_overlay.queues.erase(unit_id)
		_task_overlay.selection.erase(unit_id)
		_task_overlay.queue_redraw()
	if _selected_units.has(unit_id) and is_instance_valid(_selected_units[unit_id]):
		_selected_units[unit_id].set_selected(false)
	_selected_units.erase(unit_id)
	_visual_units.erase(unit_id)
	_selection_collection.erase(unit_id)
	if _unit_markers.has(unit_id):
		_unit_markers[unit_id].hide()
		_unit_markers[unit_id].queue_free()
		_unit_markers.erase(unit_id)
	if focused and not _selection_collection.is_empty(): _cycle_marker_selection(false)


func _handle_control_group_key(event: InputEventKey) -> bool:
	if not event.pressed or event.echo or event.alt_pressed or event.meta_pressed or get_viewport().gui_get_focus_owner() != null: return false
	if event.keycode < KEY_0 or event.keycode > KEY_9: return false
	if not _fire_mode.is_empty() or _fast_move_armed or _attack_move_armed or _reverse_move_armed or _left_pressed or _right_pressed: return false
	var group: int = event.keycode - KEY_0
	if event.ctrl_pressed:
		if event.shift_pressed: return false
		_control_groups.save(group, _command_unit_ids(MovementSimulation.MoveMode.BASIC))
		_hud_dirty = true
		return true
	_select_control_group(group, event.shift_pressed)
	return true

func _available_control_group_units() -> Array[int]:
	var available: Array[int] = []
	for id: int in _visual_units:
		if _visual_units[id].owner_player_id == NetworkManager.local_player_id and NetworkManager.local_player_id > 0 and _visual_units[id].health > 0: available.append(id)
	return available

func _select_control_group(group: int, additive: bool) -> void:
	if replay_mode or (_menu != null and _menu.visible) or (_deployment_ui != null and _deployment_ui.owns_commands()): return
	if _camera.is_rotating() or not _fire_mode.is_empty() or _fast_move_armed or _attack_move_armed or _reverse_move_armed or _left_pressed or _right_pressed: return
	var available := _available_control_group_units()
	var current: Array[int] = []
	current.assign(_selected_units.keys())
	var result := _control_groups.select_group(group, current, available, additive, Time.get_ticks_msec()/1000.0)
	_hud_dirty = true
	if not result.changed: return
	var selection: Dictionary[int, Node3D] = {}
	var center := Vector3.ZERO
	for id: int in result.selection:
		if _visual_units.has(id):
			selection[id] = _visual_units[id]
			center += _visual_units[id].position
	_replace_selection(selection)
	if result.locate and not selection.is_empty(): _camera.focus_position(center/selection.size())

func _on_hud_group(group: int, additive: bool) -> void:
	_select_control_group(group, additive)

func _hud_unit(id: int) -> Dictionary:
	var unit: Node3D = _visual_units[id]
	var row := {"unit_id":id, "owner_player_id":unit.owner_player_id, "unit_type":unit.unit_type,
		"position":unit.position, "team_id":unit.team_id, "health":unit.health,
		"maximum_health":unit.maximum_health, "armed":unit.armed,
		"configuration":unit.definition_id if not unit.definition_id.is_empty() else "配置未配置"}
	if _unit_markers.has(id) and _unit_markers[id].member_count >= 0: row.member_count = _unit_markers[id].member_count
	if unit.owner_player_id == NetworkManager.local_player_id and NetworkManager.local_player_id > 0:
		var structure: Dictionary = presentation_source.live_structures.get(id, {})
		if structure.has("members") and not structure.members.is_empty(): row.maximum_members = structure.members.size()
		for weapon: Dictionary in structure.get("weapons", []):
			if str(weapon.definition_id) == "W_M252": row.artillery = true
			else: row.direct_fire = true
	return row

func _refresh_hud() -> void:
	_hud_dirty = false
	var map_units: Array[Dictionary] = []
	var selected: Array[Dictionary] = []
	for id: int in _visual_units:
		var unit: Node3D = _visual_units[id]
		if not is_instance_valid(unit) or unit.health <= 0 or not unit.is_visible_in_tree(): continue
		var row := _hud_unit(id)
		map_units.append(row)
		if _selected_units.has(id): selected.append(row)
	var order := BattleHUDModel.selection_order(selected)
	selected.sort_custom(func(a: Dictionary, b: Dictionary): return order.find(int(a.unit_id)) < order.find(int(b.unit_id)))
	_battle_hud.show_selection(selected, presentation_source.live_structures, NetworkManager.local_player_id)
	var current: Array[int] = []
	current.assign(_selected_units.keys())
	_battle_hud.show_control_groups(_control_groups.groups, current, _available_control_group_units())
	_battle_hud.update_map(map_units, NetworkManager.local_player_id)

func _on_hud_command(command: String) -> void:
	if _menu != null and _menu.visible: return
	if replay_mode or (_deployment_ui != null and _deployment_ui.owns_commands()): return
	match command:
		"fast": _toggle_fast_move()
		"reverse": _arm_reverse_move()
		"attack_move": _arm_attack_move()
		"ground_fire", "artillery":
			_consume_move_mode()
			_fire_mode = command
			_movement_mode_hint.text = "火炮：左键选择落点，E 退出" if command == "artillery" else "强制开火：左键选择位置，E 退出"
			_movement_mode_hint.show()

func _locate_disclosed_unit(id: int) -> void:
	if _visual_units.has(id) and is_instance_valid(_visual_units[id]) and _visual_units[id].is_visible_in_tree():
		_camera.focus_position(_visual_units[id].position)

func _ground_at(screen_position: Vector2) -> Variant:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	return Plane(Vector3.UP, movement_config.ground_height).intersects_ray(camera.project_ray_origin(screen_position), camera.project_ray_normal(screen_position))


func _view_owner_id() -> int:
	return view_player_id if replay_mode else multiplayer.get_unique_id()


func _request_move_at(screen_position: Vector2, mode: int = MovementSimulation.MoveMode.BASIC, end: Vector2 = Vector2.ZERO, dragged: bool = false, ground: Variant = null, tip: Variant = null, append: bool = false) -> void:
	if replay_mode:
		return
	_prune_selection()
	var hit: Variant = ground if ground is Vector3 else _ground_at(screen_position)
	if not hit is Vector3:
		return
	var facing := Vector3.ZERO
	if dragged:
		var end_hit: Variant = tip if tip is Vector3 else _ground_at(end)
		if not end_hit is Vector3 or (end_hit - hit).is_zero_approx():
			return
		facing = (end_hit - hit).normalized()
	# Send the owned living selection; the server filters command eligibility.
	var ids := _command_unit_ids(MovementSimulation.MoveMode.BASIC)
	if not ids.is_empty():
		NetworkManager.request_moves(ids, hit, mode, facing,append)


func _command_unit_ids(mode: int) -> Array[int]:
	var ids: Array[int] = []
	for id: int in _selected_units:
		var unit := _selected_units[id]
		if unit.owner_peer_id != _view_owner_id() or unit.health <= 0:
			continue
		if mode == MovementSimulation.MoveMode.REVERSE and unit.unit_type != UnitDefinition.UnitType.ARMORED_VEHICLE:
			continue
		if mode == MovementSimulation.MoveMode.ATTACK and not unit.armed:
			continue
		ids.append(id)
	ids.sort()
	return ids


func _cancel_right_drag() -> void:
	_right_pressed = false
	_right_dragging = false
	_right_ground = null
	if _formation_preview != null:
		for child: Node in _formation_preview.get_children():
			child.queue_free()
			child.hide()


func _update_formation_preview(end: Vector2) -> void:
	for child: Node in _formation_preview.get_children():
		child.queue_free()
		child.hide()
	if not _right_dragging:
		return
	_prune_selection()
	var ids := _command_unit_ids(_right_mode)
	var center: Variant = _right_ground
	var tip: Variant = _ground_at(end)
	if ids.is_empty() or not center is Vector3 or not tip is Vector3:
		return
	var forward: Vector3 = (tip - center).normalized()
	var side := forward.cross(Vector3.UP)
	var spacing := movement_config.unit_width + movement_config.destination_gap
	for i: int in ids.size():
		var slot: Vector3 = center + side * (i - (ids.size() - 1) * 0.5) * spacing + Vector3.UP * 0.08
		var arrow := MOVEMENT_PATH_VISUAL.new() as MeshInstance3D
		arrow.set_move_mode(_right_mode)
		_formation_preview.add_child(arrow)
		arrow.update_route(PackedVector3Array([slot - side * 0.35, slot + side * 0.35, slot, slot + forward, slot + forward * 0.7 + side * 0.2, slot + forward, slot + forward * 0.7 - side * 0.2]))


func _on_unit_positions_received(unit_ids: Array[int], positions: Array[Vector3]) -> void:
	for index: int in unit_ids.size():
		if _visual_units.has(unit_ids[index]):
			_visual_units[unit_ids[index]].position = positions[index]
			_update_unit_path(unit_ids[index])


func _request_stop_selected() -> void:
	if replay_mode:
		return
	_prune_selection()
	var unit_ids: Array[int] = []
	for unit_id: int in _selected_units:
		if _selected_units[unit_id].owner_peer_id == _view_owner_id():
			unit_ids.append(unit_id)
	if not unit_ids.is_empty():
		NetworkManager.request_stops(unit_ids)


func _on_unit_stops_received(unit_ids: Array[int], positions: Array[Vector3]) -> void:
	for index: int in unit_ids.size():
		var unit_id := unit_ids[index]
		if not _visual_units.has(unit_id):
			continue
		var unit := _visual_units[unit_id]
		unit.position = positions[index]
		if unit.owner_peer_id == _view_owner_id():
			_clear_unit_path(unit_id)


func _on_unit_move_targets_received(unit_ids: Array[int], positions: Array[Vector3]) -> void:
	for index: int in unit_ids.size():
		var unit_id := unit_ids[index]
		if not _visual_units.has(unit_id):
			continue
		if _visual_units[unit_id].owner_peer_id != _view_owner_id():
			continue
		_clear_unit_path(unit_id)
		_move_targets[unit_id] = positions[index]


func _on_unit_move_paths_received(unit_ids: Array[int], paths: Array[PackedVector3Array]) -> void:
	for index: int in unit_ids.size():
		var unit_id := unit_ids[index]
		if not _visual_units.has(unit_id) or not _move_targets.has(unit_id):
			continue
		if _visual_units[unit_id].owner_peer_id != _view_owner_id() or paths[index].size() < 2:
			continue
		_route_points[unit_id] = paths[index]
		_route_progress[unit_id] = 0
		_update_unit_path(unit_id)


func _update_unit_path(unit_id: int) -> void:
	if not _move_targets.has(unit_id):
		return
	var unit := _visual_units[unit_id]
	var target := _move_targets[unit_id]
	if unit.position.distance_to(target) <= 0.001:
		_clear_unit_path(unit_id)
		return
	if not _route_points.has(unit_id):
		return
	if not _movement_paths.has(unit_id):
		var path := MOVEMENT_PATH_VISUAL.new() as MeshInstance3D
		path.name = "MovementPath_%d" % unit_id
		add_child(path)
		_movement_paths[unit_id] = path
	if not replay_mode:
		_movement_paths[unit_id].set_move_mode(_path_modes.get(unit_id,MovementSimulation.MoveMode.BASIC))
		_movement_paths[unit_id].visible = _selected_units.has(unit_id)
	# The path is presentation only, slightly above the prototype ground plane.
	var remaining := _remaining_visual_route(unit_id, unit.position)
	for index: int in remaining.size():
		var point := remaining[index]
		point.y = movement_config.ground_height + 0.04
		remaining[index] = _units.transform * point
	_movement_paths[unit_id].update_route(remaining)


func _remaining_visual_route(unit_id: int, position: Vector3) -> PackedVector3Array:
	var route := _route_points[unit_id]
	var best := _route_progress[unit_id]
	var distance := INF
	# Find visual progress using replicated positions; this never moves a unit.
	for index: int in range(best, route.size() - 1):
		var closest := Geometry3D.get_closest_point_to_segment(position, route[index], route[index + 1])
		var candidate_distance := position.distance_squared_to(closest)
		if candidate_distance <= distance:
			distance = candidate_distance
			best = index
	_route_progress[unit_id] = best
	var points := PackedVector3Array([position])
	var segment_start := Geometry3D.get_closest_point_to_segment(position, route[best], route[best + 1])
	if segment_start.is_equal_approx(route[best]) and not position.is_equal_approx(route[best]):
		points.append(route[best])
	points.append_array(route.slice(best + 1))
	return points


func _clear_unit_path(unit_id: int) -> void:
	if _movement_paths.has(unit_id):
		_movement_paths[unit_id].hide()
		_movement_paths[unit_id].queue_free()
		_movement_paths.erase(unit_id)
	_move_targets.erase(unit_id)
	_route_points.erase(unit_id)
	_route_progress.erase(unit_id)
	_path_modes.erase(unit_id)


func _clear_movement_paths() -> void:
	for unit_id: int in _move_targets.keys():
		_clear_unit_path(unit_id)
