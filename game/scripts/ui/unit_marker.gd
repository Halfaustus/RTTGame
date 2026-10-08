class_name UnitMarker
extends Button

signal chosen(shift: bool, double_click: bool)
signal cancel_requested
const STYLE = preload("res://data/ui/unit_marker_style.tres")
var style: UnitMarkerStyle = STYLE
var unit_kind := UnitDefinition.UnitType.INFANTRY
var armed := true
var player_id := 0
var viewer_player_id := -1 # -1 retains frozen historical presentation.
var team_id := 1
var is_order := false
var selected := false
var member_count := -1
var personnel_state := "normal"
var invalid_destination := false
var temporary_role := ""
var module_levels: Array = []
var laser_state := "inactive"
var hold_fire := false
var engaged := false
var return_fire_only := false
var carried_personnel := 0
var mixed_cargo := false
var fire_progress: Dictionary = {}
var health_known := false
var health_ratio := 0.0

func apply_health(health: float, maximum_health: float) -> void:
	health_known = is_finite(health) and is_finite(maximum_health) and maximum_health > 0.0 and health >= 0.0
	if health_known:
		health_ratio = clampf(health / maximum_health,0.0,1.0)
	refresh()

func apply_status(status: Dictionary) -> void:
	personnel_state = status.get("personnel_state","normal")
	module_levels = status.get("modules",[]).duplicate()
	laser_state = status.get("laser","inactive")
	hold_fire = status.get("hold_fire",false)
	engaged = status.get("engaged",false)
	return_fire_only = status.get("return_fire_only",false)
	carried_personnel = status.get("carried_personnel",0)
	mixed_cargo = status.get("mixed_cargo",false)
	fire_progress = status.get("fire_progress",{}).duplicate()
	refresh()

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP if is_order else Control.MOUSE_FILTER_PASS
	custom_minimum_size = style.body_size
	size = style.body_size
	for state: String in ["normal","hover","pressed","disabled","focus"]:
		add_theme_stylebox_override(state,StyleBoxEmpty.new())
	# Fixed anchors remain compatible with the frozen historical presentation.
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

func project(camera: Camera3D, world_position: Vector3, zoom_scale: float = 1.0) -> void:
	scale = Vector2.ONE * zoom_scale
	visible = camera != null and not camera.is_position_behind(world_position)
	if visible: position = camera.unproject_position(world_position)-style.body_size*scale*0.5

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
	var is_enemy := team_id == 2 and viewer_player_id >= 0
	draw_rect(body,style.gray_fill)
	# This consumes an eventual synchronized state; no new panic simulation.
	if not is_order and personnel_state in ["panic","disabled"]:
		var tint := Color.YELLOW if personnel_state == "panic" else Color.RED
		for strip: int in int(style.body_size.y):
			draw_rect(Rect2(0,strip,style.body_size.x,1),tint.lerp(style.gray_fill,strip/maxf(1,style.body_size.y-1)))
	draw_rect(body,Color(1.0,0.25,0.15) if is_enemy else style.color_for(player_id,viewer_player_id),false,style.border_width)
	if selected: draw_rect(body.grow(style.selection_margin),Color.WHITE,false,style.selection_width)
	if not is_order and module_levels.size() == 4:
		for slot: int in 3:
			var grade: int = module_levels[[0,2,3][slot]]
			if grade > 0: draw_rect(Rect2(style.body_size.x+4,slot*13,8,8),Color.YELLOW if grade == 1 else Color.RED)
	var font := ThemeDB.fallback_font
	var has_fire_progress := not fire_progress.is_empty() and float(fire_progress.get("remaining_seconds",0.0)) > 0
	if not is_order:
		var work := ["L" if laser_state != "inactive" else "", "×" if hold_fire else "", "!" if engaged else ""]
		for slot: int in work.size():
			if not work[slot].is_empty(): draw_string(font,Vector2(-13,11+slot*13),work[slot],HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color.YELLOW if slot == 0 and laser_state == "paused" else Color.WHITE)
		if return_fire_only: draw_string(font,Vector2(-27,11),"H",HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color.WHITE)
		if mixed_cargo or carried_personnel > 0:
			var load_text := "▣" if mixed_cargo else str(carried_personnel)
			var load_width := font.get_string_size(load_text,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x
			draw_string(font,Vector2((style.body_size.x-load_width)/2,-4),load_text,HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color.WHITE)
		var fire_bar_y := style.body_size.y+style.count_gap
		if has_fire_progress and unit_kind in [UnitDefinition.UnitType.ARMORED_VEHICLE,UnitDefinition.UnitType.INFANTRY]:
			var fire_bar := Rect2(0,fire_bar_y,style.body_size.x,3.0)
			draw_rect(fire_bar,Color(0.15,0.15,0.15))
			fire_bar.size.x *= clampf(float(fire_progress.get("progress",0.0)),0.0,1.0)
			draw_rect(fire_bar,Color.WHITE)
		if unit_kind == UnitDefinition.UnitType.ARMORED_VEHICLE:
			var health_bar_y := fire_bar_y+3.0+style.count_gap
			var health_bar := Rect2(0,health_bar_y,style.body_size.x,6.0)
			if health_known:
				draw_rect(health_bar,Color(0.15,0.15,0.15))
				health_bar.size.x *= health_ratio
				draw_rect(health_bar,Color(1.0,0.25,0.15) if is_enemy else Color(0.2,0.85,0.35))
	var symbol := "⊘" if is_order and invalid_destination else style.symbol_for(unit_kind,armed)
	var width := font.get_string_size(symbol,HORIZONTAL_ALIGNMENT_LEFT,-1,style.font_size).x
	var texture := style.texture_for(unit_kind,armed)
	if viewer_player_id >= 0 and not invalid_destination:
		TemporaryUnitBadge.draw_badge(self,style.body_size/2-Vector2(0,4),unit_kind == UnitDefinition.UnitType.ARMORED_VEHICLE)
		var caption := TemporaryUnitBadge.caption(temporary_role)
		if not caption.is_empty():
			var caption_width := font.get_string_size(caption,HORIZONTAL_ALIGNMENT_LEFT,-1,10).x
			draw_string(font,Vector2((style.body_size.x-caption_width)/2,style.body_size.y-3),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,10,Color.WHITE)
	elif texture != null and not invalid_destination:
		draw_texture_rect(texture,Rect2((style.body_size-style.identification_size)/2,style.identification_size),false)
	else:
		draw_string(font,Vector2((style.body_size.x-width)/2,style.body_size.y/2+style.font_size/3.0),symbol,HORIZONTAL_ALIGNMENT_LEFT,-1,style.font_size,Color.WHITE)
	if not is_order and unit_kind == UnitDefinition.UnitType.INFANTRY and member_count >= 0:
		var count := str(member_count)
		var count_width := font.get_string_size(count,HORIZONTAL_ALIGNMENT_LEFT,-1,style.count_font_size).x
		var count_baseline := style.body_size.y+style.count_font_size+style.count_gap
		if viewer_player_id >= 0 or has_fire_progress:
			count_baseline += 3.0+style.count_gap
		draw_string(font,Vector2((style.body_size.x-count_width)/2,count_baseline),count,HORIZONTAL_ALIGNMENT_LEFT,-1,style.count_font_size,Color.WHITE)
