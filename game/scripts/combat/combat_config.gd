class_name CombatConfig
extends Resource

@export var player_team_id: int = 1
@export var rebel_team_id: int = 2
@export var player_definitions: Array[UnitDefinition] = []
@export var rebel_definition: UnitDefinition
@export var rebel_positions: Array[Vector3] = []
