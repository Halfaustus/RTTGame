class_name SimulationTimeline
extends RefCounted

const PHASES := ["session", "commands", "movement", "combat", "record", "replication"]

var tick_hz: int
var tick := 0
var sequence := -1
var phase := "idle"
var records: Array[Dictionary] = []


func _init(frequency: int = 60) -> void:
	assert(frequency > 0)
	tick_hz = frequency


func begin_tick() -> void:
	assert(phase == "idle")
	tick += 1
	sequence = -1
	records.clear()
	phase = "session"


func enter_phase(next: String) -> void:
	assert(PHASES.has(next) and PHASES.find(next) >= PHASES.find(phase))
	phase = next


func append(kind: String, type: String, payload: Dictionary) -> Dictionary:
	assert(phase in PHASES and phase != "replication")
	sequence += 1
	var record := {"tick": tick, "sequence": sequence, "phase": phase,
		"kind": kind, "type": type, "payload": payload.duplicate(true)}
	records.append(record)
	return record


func cursor() -> Dictionary:
	return {"tick": tick, "sequence": sequence}


func finish_tick() -> void:
	assert(phase == "replication")
	phase = "idle"


func seconds_per_tick() -> float:
	return 1.0 / tick_hz
