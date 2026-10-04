class_name UnitMarkerStyle
extends Resource

# Temporary UI parameters and replaceable identification glyphs.
@export var body_size := Vector2(64,40)
@export var border_width := 2.0
@export var font_size := 18
@export var count_font_size := 14
@export var count_gap := 2.0
@export var selection_margin := 2.0
@export var selection_width := 1.0
@export var order_brightness := 0.45
@export var gray_fill := Color(0.45,0.45,0.45)
@export var symbols: Dictionary = {"infantry":"I","armored_vehicle":"▰","unarmed":"○"}
@export var textures: Dictionary = {}
@export var identification_size := Vector2(24,24)
@export var player_colors: Dictionary = {0:Color(0.9,0.25,0.2),1:Color(0.2,0.6,1),2:Color(0.3,0.85,0.4)}

func symbol_for(kind: int, armed: bool = true) -> String:
	return symbols.get(key_for(kind,armed),"?")
func key_for(kind: int, armed: bool) -> String:
	return "armored_vehicle" if kind == UnitDefinition.UnitType.ARMORED_VEHICLE else ("infantry" if armed else "unarmed")
func texture_for(kind: int, armed: bool = true) -> Texture2D:
	return textures.get(key_for(kind,armed))
func color_for(player: int) -> Color:
	return player_colors.get(player,Color.WHITE)
