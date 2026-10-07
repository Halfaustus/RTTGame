class_name TaskQueueOverlay
extends Control

var camera: Camera3D
var queues: Dictionary = {}
var selection: Array[int] = []
var units: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _process(_delta: float) -> void:
	if not selection.is_empty(): queue_redraw()

func _draw() -> void:
	if camera == null: return
	for id: int in selection:
		var tasks: Array = queues.get(id,[])
		for index: int in tasks.size():
			var task: Dictionary = tasks[index]
			var point: Vector3 = task.target
			if camera.is_position_behind(point): continue
			var target := camera.unproject_position(point)
			var color: Color = Color.RED if task.type != "move" else {0:Color.WHITE,1:Color.BLUE,2:Color.YELLOW,3:Color.YELLOW}.get(task.mode,Color.WHITE)
			draw_string(ThemeDB.fallback_font,target+Vector2(6,-6),str(index+1),HORIZONTAL_ALIGNMENT_LEFT,-1,16,color)
			if task.type != "move":
				draw_arc(target,6,0,TAU,16,color,1.5)
				draw_line(target-Vector2(9,0),target+Vector2(9,0),color,1.5)
				draw_line(target-Vector2(0,9),target+Vector2(0,9),color,1.5)
			if index == 0:
				# Movement already has its actual path; ground fire uses an indicator line.
				if task.type != "move" and units.has(id) and not camera.is_position_behind(units[id].position):
					draw_dashed_line(camera.unproject_position(units[id].position),target,color,1.5,6)
				continue
			if task.type == "move":
				var path: PackedVector3Array = task.get("path",PackedVector3Array())
				if path.is_empty():
					draw_line(target-Vector2(5,5),target+Vector2(5,5),Color.RED,2)
					draw_line(target-Vector2(5,-5),target+Vector2(5,-5),Color.RED,2)
				for step: int in path.size()-1:
					if not camera.is_position_behind(path[step]) and not camera.is_position_behind(path[step+1]):
						draw_dashed_line(camera.unproject_position(path[step]),camera.unproject_position(path[step+1]),color,1.5,6)
				draw_line(target,target+Vector2(-5,-6),color,1.5)
				draw_line(target,target+Vector2(5,-6),color,1.5)
				continue
			var start: Vector3 = tasks[index-1].target
			if camera.is_position_behind(start): continue
			var a := camera.unproject_position(start)
			draw_dashed_line(a,target,color,1.5,6.0)
