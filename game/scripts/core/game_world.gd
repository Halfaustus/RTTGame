extends Node3D

const UNIT_SCENE: PackedScene = preload("res://scenes/units/unit.tscn")
const TEST_UNIT_SPACING: float = 3.0
const TEST_DISPLAY_ORIGIN: Vector3 = Vector3(0.0, 0.5, 100.0)

var _visual_units: Dictionary[int, Node3D] = {}

@onready var _units: Node3D = $Units


func _ready() -> void:
	NetworkManager.unit_spawn_received.connect(_on_unit_spawn_received)


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
