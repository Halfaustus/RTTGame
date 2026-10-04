class_name UnitMarker
extends Button

signal chosen(shift: bool, double_click: bool)
signal cancel_requested
const STYLE = preload("res://data/ui/unit_marker_style.tres")
var style: UnitMarkerStyle = STYLE
var unit_kind := UnitDefinition.UnitType.INFANTRY
var armed := true
var player_id := 0
var is_order := false
var selected := false
var member_count := -1
var personnel_state := "normal"
var invalid_destination := false

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP if is_order else Control.MOUSE_FILTER_PASS
	custom_minimum_size = style.body_size
	size = style.body_size
	for state: String in ["normal","hover","pressed","disabled","focus"]:
		add_theme_stylebox_override(state,StyleBoxEmpty.new())
	# Reserved layout hooks only; status indicators are deferred in 0.5C.
	for location: String in ["LeftStatusSlots","RightStatusSlots","TopStatusSlots","BottomStatusSlots"]:
		var hook := Control.new()
		hook.name = location
		hook.mouse_filter = Control.MOUSE_FILTER_IGNORE
		match location:
			"LeftStatusSlots": hook.position = Vector2(-style.identification_size.x-style.count_gap,0)
			"RightStatusSlots": hook.position = Vector2(style.body_size.x+style.count_gap,0)
			"TopStatusSlots": hook.position = Vector2(0,-style.identification_size.y-style.count_gap)
			"BottomStatusSlots": hook.position = Vector2(0,style.body_size.y+style.count_gap)
		add_child(hook)
	refresh()

func refresh() -> void:
	modulate = Color(style.order_brightness,style.order_brightness,style.order_brightness) if is_order else Color.WHITE
	queue_redraw()

func project(camera: Camera3D, world_position: Vector3) -> void:
	visible = camera != null and not camera.is_position_behind(world_position)
	if visible: position = camera.unproject_position(world_position)-style.body_size*0.5

func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton: return
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and not disabled: chosen.emit(event.shift_pressed,event.double_click)
		accept_event()
	elif event.button_index == MOUSE_BUTTON_RIGHT and is_order:
		if event.pressed and not disabled: cancel_requested.emit()
		accept_event()

func _draw() -> void:
	var body := Rect2(Vector2.ZERO,style.body_size)
	draw_rect(body,style.gray_fill)
	# This consumes an eventual synchronized state; no new panic simulation.
	if not is_order and personnel_state in ["panic","disabled"]:
		var tint := Color.YELLOW if personnel_state == "panic" else Color.RED
		for strip: int in int(style.body_size.x):
			draw_rect(Rect2(strip,0,1,style.body_size.y),tint.lerp(style.gray_fill,strip/style.body_size.x))
	draw_rect(body,style.color_for(player_id),false,style.border_width)
	if selected: draw_rect(body.grow(style.selection_margin),Color.WHITE,false,style.selection_width)
	var font := ThemeDB.fallback_font
	var symbol := "⊘" if is_order and invalid_destination else style.symbol_for(unit_kind,armed)
	var width := font.get_string_size(symbol,HORIZONTAL_ALIGNMENT_LEFT,-1,style.font_size).x
	var texture := style.texture_for(unit_kind,armed)
	if texture != null and not invalid_destination:
		draw_texture_rect(texture,Rect2((style.body_size-style.identification_size)/2,style.identification_size),false)
	else:
		draw_string(font,Vector2((style.body_size.x-width)/2,style.body_size.y/2+style.font_size/3.0),symbol,HORIZONTAL_ALIGNMENT_LEFT,-1,style.font_size,Color.WHITE)
	if not is_order and unit_kind == UnitDefinition.UnitType.INFANTRY and member_count >= 0:
		var count := str(member_count)
		var count_width := font.get_string_size(count,HORIZONTAL_ALIGNMENT_LEFT,-1,style.count_font_size).x
		draw_string(font,Vector2((style.body_size.x-count_width)/2,style.body_size.y+style.count_font_size+style.count_gap),count,HORIZONTAL_ALIGNMENT_LEFT,-1,style.count_font_size,Color.WHITE)
