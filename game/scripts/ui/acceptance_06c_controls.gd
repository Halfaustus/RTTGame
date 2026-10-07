class_name Acceptance06CControls
extends PanelContainer

# Explicit three-process acceptance tool. Coordinates are requests, never damage.
var owned_selection: Callable
var axes: Array[SpinBox] = []
var structure_lookup: Callable
var observer: TextEdit
var elapsed := 0.0

func _ready() -> void:
	position = Vector2(360,52)
	var column := VBoxContainer.new()
	add_child(column)
	var label := Label.new()
	label.text = "TEST ONLY 0.6C 精确单发\n先选己方射手；参数为服务器验证的 G 请求"
	column.add_child(label)
	var row := HBoxContainer.new()
	column.add_child(row)
	for index: int in 3:
		var caption := Label.new()
		caption.text = ["X","Y","Z"][index]
		row.add_child(caption)
		var input := SpinBox.new()
		input.min_value = -200
		input.max_value = 200
		input.step = 0.01
		input.value = [-3.0,0.0,96.0][index]
		row.add_child(input)
		axes.append(input)
	var send := Button.new()
	send.focus_mode = Control.FOCUS_NONE
	send.text = "向所选己方单位发送 G 单发"
	send.pressed.connect(func():
		_release_editor_focus()
		if owned_selection.is_valid(): NetworkManager.request_ground_fire(owned_selection.call(),Vector3(axes[0].value,axes[1].value,axes[2].value),false,1))
	column.add_child(send)
	if structure_lookup.is_valid():
		var move := Button.new()
		move.focus_mode = Control.FOCUS_NONE
		move.text = "移动所选己方单位到 XYZ（TEST ONLY）"
		move.pressed.connect(func():
			_release_editor_focus()
			if owned_selection.is_valid(): NetworkManager.request_moves(owned_selection.call(),Vector3(axes[0].value,0,axes[2].value)))
		column.add_child(move)
		var probe := Button.new()
		probe.focus_mode = Control.FOCUS_NONE
		probe.text = "模块验收：向所选己方装甲单发（真实弹丸）"
		probe.pressed.connect(func(): _release_editor_focus(); NetworkManager.request_acceptance_module_probe(owned_selection.call()))
		column.add_child(probe)
		for mode: int in [MovementSimulation.MoveMode.FAST,MovementSimulation.MoveMode.ATTACK]:
			var move_mode := Button.new()
			move_mode.focus_mode = Control.FOCUS_NONE
			move_mode.text = "快速移动到 XYZ" if mode == MovementSimulation.MoveMode.FAST else "攻击移动到 XYZ"
			move_mode.pressed.connect(func():
				_release_editor_focus()
				NetworkManager.request_moves(owned_selection.call(),Vector3(axes[0].value,0,axes[2].value),mode))
			column.add_child(move_mode)
		for enabled: bool in [true,false]:
			var auto := Button.new()
			auto.focus_mode = Control.FOCUS_NONE
			auto.text = "开启所选单位自动攻击（验收）" if enabled else "关闭所选单位自动攻击（验收）"
			auto.pressed.connect(func(): _release_editor_focus(); NetworkManager.request_acceptance_auto(owned_selection.call(),enabled))
			column.add_child(auto)
		label.text = "TEST ONLY 0.6 A～E 单发／己方状态\n零伤压制／模块射手只用于机制验证"
		observer = TextEdit.new()
		observer.editable = false
		observer.focus_mode = Control.FOCUS_NONE
		observer.custom_minimum_size = Vector2(450,120)
		column.add_child(observer)

func _release_editor_focus() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null: focused.release_focus()

func _process(delta: float) -> void:
	if observer == null or not owned_selection.is_valid(): return
	elapsed += delta
	if elapsed < 0.2: return # TEST ONLY read-only observation cadence.
	elapsed = 0.0
	var rows: Array = []
	for id: int in owned_selection.call():
		var structure: Dictionary = structure_lookup.call(id)
		rows.append(structure if not structure.is_empty() else {"unit_id":id,"status":"等待己方结构同步"})
	observer.text = JSON.stringify(rows,"  ") if not rows.is_empty() else "请选择己方单位；此处只读服务器已授权的己方结构。"
