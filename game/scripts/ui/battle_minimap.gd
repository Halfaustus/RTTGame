class_name BattleMinimap
extends Control

var bounds := Rect2()
var units: Array[Dictionary] = []
var viewer := 0
const DOT_RADIUS := 3.0 # Presentation-only placeholder, not unit geometry.

func update_units(values: Array[Dictionary], player: int) -> void:
	units = values.duplicate(true)
	viewer = player
	queue_redraw()

func _draw() -> void:
	var area := Rect2(Vector2(8, 8), size - Vector2(16, 16))
	draw_rect(area, Color(0.07, 0.10, 0.12))
	draw_rect(area, Color(0.4, 0.5, 0.55), false)
	for unit: Dictionary in units:
		if not unit.get("position") is Vector3 or not unit.position.is_finite(): continue
		var color := Color.DODGER_BLUE if int(unit.get("owner_player_id", 0)) == viewer and viewer > 0 else Color.GREEN
		if int(unit.get("team_id", 1)) != 1: color = Color.RED
		draw_circle(BattleHUDModel.map_point(unit.position, bounds, area), DOT_RADIUS, color)
