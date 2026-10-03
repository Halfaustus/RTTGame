extends Control

var _rectangle: Rect2


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func show_rectangle(rectangle: Rect2) -> void:
	_rectangle = rectangle
	visible = true
	queue_redraw()


func _draw() -> void:
	draw_rect(_rectangle, Color(0.2, 1.0, 0.2, 0.12))
	draw_rect(_rectangle, Color(0.2, 1.0, 0.2, 0.9), false, 2.0)
