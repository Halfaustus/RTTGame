extends Node3D

const UNIT_SCENE: PackedScene = preload("res://scenes/units/unit.tscn")
const TEST_UNIT_SPACING: float = 3.0
const TEST_DISPLAY_ORIGIN: Vector3 = Vector3(0.0, 0.5, 100.0)
const UNIT_PICK_MASK: int = 2
const PICK_DISTANCE: float = 1000.0

var _visual_units: Dictionary[int, Node3D] = {}
var _selected_unit: Node3D = null
var _pending_clicks: Array[Vector2] = []

@onready var _units: Node3D = $Units


func _ready() -> void:
	NetworkManager.unit_spawn_received.connect(_on_unit_spawn_received)
	multiplayer.server_disconnected.connect(_clear_selection)
	set_physics_process(false)


func _unhandled_input(event: InputEvent) -> void:
	if multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_pending_clicks.append(event.position)
		set_physics_process(true)
		get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	# Query physics in its tick, and do no per-frame picking when idle.
	for screen_position: Vector2 in _pending_clicks:
		_select_unit(_pick_unit(screen_position))
	_pending_clicks.clear()
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
	if unit == null or not _visual_units.values().has(unit):
		return null
	return unit


func _select_unit(unit: Node3D) -> void:
	# Ownership is read from the server-provided visual metadata, never changed.
	if unit != null and unit.owner_peer_id != multiplayer.get_unique_id():
		return
	if is_instance_valid(_selected_unit):
		_selected_unit.set_selected(false)
	_selected_unit = unit
	if is_instance_valid(_selected_unit):
		_selected_unit.set_selected(true)


func _clear_selection() -> void:
	_pending_clicks.clear()
	set_physics_process(false)
	_select_unit(null)


func _on_unit_spawn_received(unit_id: int, owner_peer_id: int) -> void:
	if _visual_units.has(unit_id):
		return

	var unit := UNIT_SCENE.instantiate() as Node3D
	unit.name = "Unit_%d" % unit_id
	unit.setup(unit_id, owner_peer_id)
	# Deterministic display positions only; no movement or simulation state.
	unit.position = TEST_DISPLAY_ORIGIN + Vector3((unit_id - 1) * TEST_UNIT_SPACING, 0.0, 0.0)
	_units.add_child(unit)
	_visual_units[unit_id] = unit
