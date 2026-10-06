class_name DeploymentUI
extends Control

signal input_ownership_changed(active: bool)
signal request_sent(action: String, payload: Dictionary, request_id: int)

var state: Dictionary = {}
var busy := false
var held_id := 0
var _request_id := 0
var _awaiting_id := 0
var _network: Node
var _camera: Camera3D
var _ground: Callable
var _point: OptionButton
var _move_mode: OptionButton
var _rows: VBoxContainer
var _balance: Label
var _message: Label
var _ghost: UnitMarker
var _markers: Dictionary[int, UnitMarker] = {}
var _purchase_buttons: Dictionary[String, Button] = {}
var _transport_enabled := true

func setup(camera: Camera3D, ground: Callable) -> void:
	_camera = camera
	_ground = ground

func _ready() -> void:
	_network = get_node("/root/NetworkManager")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 52)
	panel.custom_minimum_size = Vector2(330, 0)
	panel.z_index = 10
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "地面单位购买 · 临时测试目录"
	box.add_child(title)
	_balance = Label.new()
	box.add_child(_balance)
	_point = OptionButton.new()
	_point.focus_mode = Control.FOCUS_NONE
	_point.item_selected.connect(func(_index: int): _refresh_rows())
	box.add_child(_point)
	_move_mode = OptionButton.new()
	_move_mode.add_item("生成后：基本移动", MovementSimulation.MoveMode.BASIC)
	_move_mode.add_item("生成后：快速移动", MovementSimulation.MoveMode.FAST)
	_move_mode.focus_mode = Control.FOCUS_NONE
	box.add_child(_move_mode)
	_rows = VBoxContainer.new()
	box.add_child(_rows)
	_message = Label.new()
	_message.custom_minimum_size = Vector2(330, 0)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_message)
	_ghost = UnitMarker.new()
	_ghost.is_order = true
	_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost.z_index = 20
	add_child(_ghost)
	_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_network.deployment_state_received.connect(apply_state)
	_network.deployment_result_received.connect(apply_result)
	multiplayer.server_disconnected.connect(reset_connection)
	multiplayer.connection_failed.connect(reset_connection)
	apply_state(_network.local_deployment_state)

func owns_commands() -> bool:
	return held_id != 0 or busy

func apply_state(snapshot: Dictionary) -> void:
	state = snapshot.duplicate(true)
	held_id = int(state.get("held_order_id", 0))
	var selected_point := _point.get_item_text(_point.selected) if _point.selected >= 0 else ""
	var point_ids: Array[String] = []
	for point: Dictionary in state.get("points", []): point_ids.append(point.point_id)
	var current_ids: Array[String] = []
	for index: int in _point.item_count: current_ids.append(_point.get_item_text(index))
	if current_ids != point_ids:
		_point.clear()
		for point_id: String in point_ids:
			_point.add_item(point_id)
			if point_id == selected_point: _point.select(_point.item_count-1)
	_balance.text = "余额：%d 出动分\n每 5 秒：收入 %d / 维护 %d / 净收入 %d" % [state.display_points, int(state.get("income_per_settlement", 0)), int(state.get("upkeep_per_settlement", 0)), int(state.get("net_income_per_settlement", 0))] if not state.is_empty() else "等待服务器账户…"
	_refresh_rows()
	_refresh_markers()
	input_ownership_changed.emit(owns_commands())

func apply_result(result: Dictionary) -> void:
	if result.get("request_type", "") == "generated":
		_message.text = "单位 #%d 已部署%s" % [result.unit_id, "：" + str(result.notice) if not str(result.notice).is_empty() else ""]
		return
	if _awaiting_id == 0 or int(result.get("request_id", 0)) != _awaiting_id:
		return
	busy = false
	_awaiting_id = 0
	_message.text = "服务器拒绝：" + str(result.get("reason", "unknown")) if not result.ok else ("拿起兵牌：左键放置，右键或 E 取消退款" if held_id else "服务器已确认操作")
	_refresh_rows()
	input_ownership_changed.emit(owns_commands())

func reset_connection() -> void:
	busy = false
	_awaiting_id = 0
	apply_state({})
	_message.text = "连接已结束，购买不可用"

func _refresh_rows() -> void:
	# Keep button identities through frequent countdown snapshots. Replacing a
	# pressed button before release loses its pressed signal and blocks buying.
	var live := {}
	for entry: Dictionary in state.get("catalog", []):
		var counts: Dictionary = state.cards[entry.config_id]
		var remaining: int = maxi(0, int(entry.maximum_present) - int(counts.present) - int(counts.pending))
		live[entry.config_id] = true
		if not _purchase_buttons.has(entry.config_id):
			var created := Button.new()
			created.focus_mode = Control.FOCUS_NONE
			created.pressed.connect(buy.bind(str(entry.config_id)))
			_rows.add_child(created)
			_purchase_buttons[entry.config_id] = created
		var button: Button = _purchase_buttons[entry.config_id]
		button.text = "%s\n部署 %d · 价值 %d · 剩余 %d" % [_name_for(entry.config_id),entry.sortie_points,entry.value_points,remaining]
		button.disabled = owns_commands() or remaining == 0 or state.balance < entry.sortie_points or _point.selected < 0
	for id: String in _purchase_buttons.keys():
		if not live.has(id):
			var obsolete := _purchase_buttons[id]
			_rows.remove_child(obsolete)
			obsolete.queue_free()
			_purchase_buttons.erase(id)
	_point.disabled = owns_commands()

func buy(config_id: String) -> void:
	if owns_commands() or _point.selected < 0 or state.is_empty():
		return
	_send("buy", {"config_id":config_id,"point_id":_point.get_item_text(_point.selected)})

func pickup(order_id: int) -> void:
	if not owns_commands():
		_send("pickup", {"order_id":order_id,"destination":Vector3.ZERO})

func place(destination: Vector3) -> void:
	if held_id != 0 and not busy:
		_send("place", {"order_id":held_id,"destination":destination,"mode":_move_mode.get_selected_id()})

func cancel() -> void:
	if held_id != 0 and not busy:
		_send("cancel", {"order_id":held_id,"destination":Vector3.ZERO})

func cancel_placed(order_id: int) -> void:
	if not owns_commands(): _send("cancel",{"order_id":order_id,"destination":Vector3.ZERO})

func _send(action: String, payload: Dictionary) -> void:
	if _camera != null and _camera.is_rotating():
		return
	if _transport_enabled and multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		reset_connection()
		return
	_request_id += 1
	_awaiting_id = _request_id
	busy = true
	_message.text = "等待服务器确认…"
	_refresh_rows()
	input_ownership_changed.emit(true)
	request_sent.emit(action, payload.duplicate(true), _request_id)
	if _transport_enabled:
		if action == "buy":
			_network.request_buy_deployment(payload.config_id, payload.point_id, _request_id)
		else:
			_network.request_edit_deployment(action, payload.order_id, payload.destination, _request_id, payload.get("mode", MovementSimulation.MoveMode.BASIC))

# Right/E cancellation also works over the purchase panel. GUI left clicks are
# left to Control and never reach ground placement or ordinary unit selection.
func _input(event: InputEvent) -> void:
	if not owns_commands() or (_camera != null and _camera.is_rotating()):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			cancel()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.keycode == KEY_E and get_viewport().gui_get_focus_owner() == null:
		if event.pressed and not event.echo and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
			cancel()
		get_viewport().set_input_as_handled()

func handle_world_input(event: InputEvent) -> bool:
	if not owns_commands():
		return false
	if get_viewport().gui_get_focus_owner() != null:
		return false
	if event is InputEventKey:
		if event.keycode == KEY_ESCAPE:
			return false
		if event.keycode == KEY_E and event.pressed and not event.echo and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
			cancel()
		return event.keycode in [KEY_E, KEY_F, KEY_Q, KEY_R]
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		if event.pressed and not busy:
			if event.button_index == MOUSE_BUTTON_RIGHT:
				cancel()
			elif _ground.is_valid():
				var destination: Variant = _ground.call(event.position)
				if destination is Vector3:
					place(destination)
		return true
	return event is InputEventMouseMotion

func _refresh_markers() -> void:
	var live := {}
	for order: Dictionary in state.get("orders", []):
		if order.status not in ["placed", "countdown", "waiting"] or not order.destination is Vector3:
			continue
		live[order.order_id] = true
		if not _markers.has(order.order_id):
			var button := UnitMarker.new()
			button.is_order = true
			button.chosen.connect(func(_shift: bool,_double: bool): pickup(order.order_id))
			button.cancel_requested.connect(cancel_placed.bind(int(order.order_id)))
			add_child(button)
			_markers[order.order_id] = button
		_configure_marker(_markers[order.order_id],order)
		_markers[order.order_id].mouse_filter = Control.MOUSE_FILTER_IGNORE if owns_commands() else Control.MOUSE_FILTER_STOP
	for id: int in _markers.keys():
		if not live.has(id):
			_markers[id].queue_free()
			_markers[id].hide()
			_markers.erase(id)

func _process(_delta: float) -> void:
	_ghost.visible = held_id != 0
	_ghost.position = get_viewport().get_mouse_position()-_ghost.style.body_size*0.5
	if held_id != 0 and _ground.is_valid():
		var destination: Variant = _ground.call(get_viewport().get_mouse_position())
		var movement: MovementConfig = preload("res://data/prototype_movement.tres")
		_ghost.invalid_destination = not destination is Vector3
		if destination is Vector3:
			_ghost.invalid_destination = not destination.is_finite() or destination.x < movement.minimum_xz.x or destination.x > movement.maximum_xz.x or destination.z < movement.minimum_xz.y or destination.z > movement.maximum_xz.y
	for order: Dictionary in state.get("orders", []):
		if order.order_id == held_id: _configure_marker(_ghost,order)
	for order: Dictionary in state.get("orders", []):
		if not _markers.has(order.order_id) or _camera == null:
			continue
		var button: UnitMarker = _markers[order.order_id]
		button.disabled = owns_commands() or order.status not in ["placed", "countdown", "waiting"]
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE if owns_commands() else Control.MOUSE_FILTER_STOP
		button.project(_camera,order.destination)

func _configure_marker(marker: UnitMarker, order: Dictionary) -> void:
	marker.player_id = int(state.get("player_id",0))
	marker.viewer_player_id = int(state.get("player_id",0))
	for entry: Dictionary in state.get("catalog",[]):
		if entry.config_id == order.config_id:
			marker.unit_kind = int(entry.unit_type)
			marker.armed = bool(entry.armed)
	marker.set_meta("order_status",order.status)
	marker.set_meta("remaining_seconds",order.get("remaining_seconds",0.0))
	marker.refresh()

static func status_text(order: Dictionary) -> String:
	match order.status:
		"held": return "待放置"
		"placed": return "已放置 · 倒计时未启用"
		"countdown": return "倒计时：%.1f 秒" % float(order.get("remaining_seconds", 0))
		"waiting": return "等待部署"
	return "未启用部署状态"

static func _name_for(config_id: String) -> String:
	return {"test.armored":"装甲车辆", "test.rifle":"武装步兵", "test.unarmed":"无武器步兵"}.get(config_id, config_id)
