extends "res://probe.gd"

const PROMPT := 10
const ACTION := 11
const FIRST := 16
const DELAY := [3, 3, 3, 3, 7, 3, 3, 6, 3]
var ring: Array[Dictionary] = []
var anchors := {}
var handled := {}
var actions: Array[Dictionary] = []
var flights: Array[Dictionary] = []
var history_results := {}
var per_seat := {}
var sample_trace: Array[Dictionary] = []
var different_now := 0
var flight_hits := 0

func on_connected(id: int) -> void:
	anchors[id] = {}
	handled[id] = {}
	per_seat[id] = {}
	super.on_connected(id)

func server_receive(id: int, words: PackedInt32Array) -> void:
	if words[0] != ACTION:
		super.server_receive(id, words)
		return
	if words.size() != 4 or not anchors.has(id) or not anchors[id].has(words[1]):
		invalid += 1
		return
	var token := words[1]
	var anchor: int = anchors[id][token]
	var trial := anchor - FIRST
	# Each connection has its own simulated clock origin. The anchor issued
	# by the server constrains the mapped tick; clients cannot choose history.
	var mapped: int = words[2] - (1000 + 3 * int(seats[id]))
	actions.append({"id": id, "token": token, "trial": trial, "mapped": mapped,
		"anchor": anchor, "due": maxi(tick + 1, anchor + int(DELAY[trial])),
		"projectile": words[3] == 1})

func pose(at: int) -> Dictionary:
	var phase := at % 8
	var near := phase in [0, 1, 2, 6, 7]
	return {"tick": at, "origin": 10 * at, "target": 10 * at + (2 if near else 12),
		"guard": phase == 1, "shield": phase == 2, "moving_obstacle": (at - 4) * 10 + 4}

func melee(s: Dictionary) -> String:
	if s.target - s.origin > 3:
		return "miss"
	if s.guard:
		return "guard"
	if s.shield:
		return "shield"
	return "hit"

func resolve(a: Dictionary, current: Dictionary) -> String:
	if handled[a.id].has(a.token):
		return "duplicate"
	handled[a.id][a.token] = true
	if a.mapped > tick:
		return "future"
	if a.mapped != a.anchor:
		return "unbound"
	if tick - a.mapped > 6:
		return "expired"
	var sample: Dictionary = ring[a.mapped % 7]
	if sample.tick != a.mapped:
		return "missing"
	if a.projectile:
		# Only release origin is rewound. Collision uses each new authority tick.
		flights.append({"x": sample.origin, "release": sample.tick, "born": tick, "id": a.id})
		return "release"
	var result := melee(sample)
	if a.trial == 0 and result != melee(current):
		different_now += 1
	return result

func _physics_process(delta: float) -> bool:
	var previous_size := cost_us.size()
	super._physics_process(delta)
	if previous_size == cost_us.size():
		return false
	var begin := Time.get_ticks_usec()
	var current := pose(tick)
	if ring.size() < 7:
		ring.resize(7)
	ring[tick % 7] = current
	for projectile in flights.duplicate():
		var old_x: int = projectile.x
		projectile.x += 4
		if old_x < current.moving_obstacle and current.moving_obstacle <= projectile.x:
			flight_hits += 1
			if seats[projectile.id] == 0:
				sample_trace.append({"release_tick": projectile.release, "admitted_tick": projectile.born,
					"collision_tick": tick, "from_x": old_x, "to_x": projectile.x,
					"obstacle_now": current.moving_obstacle})
			flights.erase(projectile)
		elif tick - projectile.born >= 8:
			flights.erase(projectile)
	var trial := tick - FIRST
	if trial >= 0 and trial < DELAY.size():
		for id: int in seats:
			var token: int = 100 * int(seats[id]) + trial
			anchors[id][token] = tick
			send(id, PackedInt32Array([PROMPT, token, tick + 1000 + 3 * int(seats[id]), trial]), true)
	for i in range(actions.size() - 1, -1, -1):
		var action := actions[i]
		if action.due > tick:
			continue
		var result := resolve(action, current)
		var key := "%d/%s" % [action.trial, result]
		history_results[key] = history_results.get(key, 0) + 1
		per_seat[action.id][key] = per_seat[action.id].get(key, 0) + 1
		if seats[action.id] == 0:
			sample_trace.append({"case": action.trial, "origin": action.anchor, "mapped": action.mapped,
				"applied": tick, "result": result, "now": melee(current)})
		actions.remove_at(i)
	cost_us[-1] += Time.get_ticks_usec() - begin
	return false

func emit_result() -> void:
	print("P0_HISTORY ", JSON.stringify({"results": history_results, "outcomes_by_seat": per_seat.values(), "counterfactuals": different_now,
		"forward_hits": flight_hits, "example": sample_trace, "samples_retained": ring.size(),
		"enet_tx_packets": net.host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_PACKETS),
		"enet_rx_packets": net.host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_PACKETS),
		"engine_static_peak_bytes": OS.get_static_memory_peak_usage()}))
	super.emit_result()
