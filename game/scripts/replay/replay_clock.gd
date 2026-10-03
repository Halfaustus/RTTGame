class_name ReplayClock
extends RefCounted

signal progress_changed(seconds: float, duration: float, tick: int)
signal playback_finished

var presentation := ReplayPresentation.new()
var status := "empty"
var elapsed_seconds := 0.0
var duration_seconds := 0.0
var current_tick := 0
var tick_hz := 0
var last_tick := 0
var error := ""

# Minimal playback control boundary. No pause/speed/seek or input resimulation.
func open(data: Dictionary, view_player_id: int = 0) -> String:
	error = presentation.open(data, view_player_id)
	if not error.is_empty():
		status = "failed"
		return error
	tick_hz = int(data.header.tick_hz)
	last_tick = int(data.last_tick)
	duration_seconds = float(last_tick) / tick_hz
	elapsed_seconds = 0.0
	current_tick = 0
	status = "ready"
	return ""

func start() -> bool:
	if status != "ready" or not presentation.apply_checkpoint():
		return false
	status = "playing"
	progress_changed.emit(elapsed_seconds, duration_seconds, current_tick)
	if last_tick == 0:
		_complete()
	return true

func advance(delta: float) -> bool:
	if status == "finished":
		return true
	if status != "playing" or not is_finite(delta) or delta < 0.0:
		return false
	elapsed_seconds = minf(duration_seconds, elapsed_seconds + delta)
	# Tiny tolerance avoids a floating accumulation delaying an exact tick boundary.
	current_tick = mini(last_tick, int(floor(elapsed_seconds * tick_hz + 0.00000001)))
	if not presentation.apply_through_tick(current_tick):
		status = "failed"
		error = "record sequence application failed"
		return false
	progress_changed.emit(elapsed_seconds, duration_seconds, current_tick)
	if current_tick == last_tick:
		_complete()
	return true

func _complete() -> void:
	elapsed_seconds = duration_seconds
	status = "finished"
	playback_finished.emit()
