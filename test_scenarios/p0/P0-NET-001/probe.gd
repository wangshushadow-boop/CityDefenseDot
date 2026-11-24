extends SceneTree

# Experiment-local integer messages. Every endpoint is a separate Godot process.
enum { START, MOVE, STATE, DRAINED, FINAL, ACK, CLOSE }
const INPUT_TICKS := 120
const AI_COUNT := 64
const SEED := 241124
const STEP_US := 1000000.0 / 30.0
var net := ENetMultiplayerPeer.new()
var server := false
var impaired := false
var client_count := 1
var actor := -1
var started := false
var final_sent := false
var finished := false
var tick := 0
var first_tick_us := 0
var seats := {}  # ENet connection ID -> controlled actor index
var drained := {}
var acknowledged := {}
var latest := PackedInt32Array()
var primary_seq := PackedInt32Array()
var reordered_inputs := 0
var last_echo_sample := 0
var echoes := PackedInt32Array()
var positions := PackedInt32Array()
var received_state := PackedInt32Array()
var final_state_tick := -1
var accepted := PackedInt32Array()
var seen := {}
var pending: Array[Dictionary] = []
var cost_us: Array[int] = []
var debt_us: Array[int] = []
var ack_age_ms: Array[int] = []
var accepted_duplicate := 0
var stale := 0
var unauthorized := 0
var duplicate := 0
var invalid := 0
var queued := 0
var dropped := 0
var forced_reorders := 0
var reordered_snapshots := 0
var snapshots := 0
var max_connections := 0
var early_disconnects := 0
var sent_bytes := 0
var recv_bytes := 0
var close_tick := -1
var final_ack_matches := 0
var flush_cost_us := 0
var simulation_end_us := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	server = args[0] == "server"
	var port := args[1].to_int()
	client_count = args[2].to_int()
	impaired = args[3] == "fault"
	Engine.max_fps = 144
	net.peer_connected.connect(on_connected)
	net.peer_disconnected.connect(on_disconnected)
	var result: Error
	if server:
		net.set_bind_ip("127.0.0.1")
		result = net.create_server(port, client_count)
	else:
		result = net.create_client("127.0.0.1", port)
	if result != OK:
		fail("ENet startup: " + error_string(result))
	elif server:
		print("P0_LISTENING")

func fail(message: String) -> void:
	finished = true
	printerr("P0_FAILURE ", message)
	quit(1)

func on_connected(id: int) -> void:
	print("P0_CONNECTION ", id)
	if not server:
		return
	seats[id] = seats.size()
	max_connections = maxi(max_connections, seats.size())
	if seats.size() != client_count:
		return
	latest.resize(client_count)
	primary_seq.resize(client_count)
	echoes.resize(client_count)
	accepted.resize(client_count)
	positions.resize(client_count + AI_COUNT)
	for peer_id: int in seats:
		seen[peer_id] = {}
		send(peer_id, PackedInt32Array([START, seats[peer_id]]), true)
	started = true

func on_disconnected(_id: int) -> void:
	if started and not final_sent and not finished:
		early_disconnects += 1
		fail("peer disconnected before final snapshot")

func send(id: int, words: PackedInt32Array, reliable: bool) -> void:
	net.set_target_peer(id)
	net.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE
	var bytes := words.to_byte_array()
	var err := net.put_packet(bytes)
	if err != OK:
		fail("ENet put_packet: " + error_string(err))
		return
	sent_bytes += bytes.size()

# Normalized over a 100-datagram cycle. Jitter is +/-15 ms per leg, plus an
# explicit hold on every 23rd datagram to exercise out-of-order delivery.
func schedule(id: int, words: PackedInt32Array, serial: int, stream: int) -> void:
	queued += 1
	if not impaired:
		send(id, words, false)
		return
	var offset := SEED + stream * 59
	if (serial * 37 + offset) % 100 < 3:
		dropped += 1
		return
	var delay_ms := 75 + (serial * 47 + offset) % 31 - 15
	if serial % 23 == 10:
		delay_ms += 100
		forced_reorders += 1
	pending.append({"due": Time.get_ticks_msec() + delay_ms, "peer": id, "data": words})

func _process(_delta: float) -> bool:
	if finished:
		return false
	if Time.get_ticks_msec() > 15000:
		fail("timeout tick=%d started=%s final=%s peer_status=%d seats=%d drained=%d ACKs=%d" % [tick, started, final_sent, net.get_connection_status(), seats.size(), drained.size(), acknowledged.size()])
		return false
	var now := Time.get_ticks_msec()
	var begin := Time.get_ticks_usec()
	var index := 0
	while index < pending.size():
		if pending[index].due <= now:
			var item := pending[index]
			pending.remove_at(index)
			send(item.peer, item.data, false)
		else:
			index += 1
	flush_cost_us += Time.get_ticks_usec() - begin
	return false

func _physics_process(_delta: float) -> bool:
	if finished:
		return false
	var begin := Time.get_ticks_usec()
	net.poll()
	while net.get_available_packet_count() > 0:
		var sender := net.get_packet_peer()
		var bytes := net.get_packet()
		recv_bytes += bytes.size()
		var words := bytes.to_int32_array()
		if words.is_empty() or bytes.size() != words.size() * 4:
			fail("invalid experiment datagram")
			return false
		if server:
			server_receive(sender, words)
		else:
			client_receive(words)
	if not started or finished:
		return false
	if first_tick_us == 0:
		first_tick_us = begin
	tick += 1
	if server and not final_sent:
		for i in range(client_count, positions.size()):
			positions[i] += 1 + (i + tick) % 3
		if tick % 2 == 0 and drained.size() < client_count:
			for id: int in seats:
				var slot: int = seats[id]
				var frame := PackedInt32Array([STATE, tick, echoes[slot]])
				frame.append_array(positions)
				schedule(id, frame, int(tick / 2.0), slot + 100)
		if drained.size() == client_count and pending.is_empty():
			for id: int in seats:
				var frame := PackedInt32Array([FINAL, tick])
				frame.append_array(positions)
				send(id, frame, true)
			final_sent = true
			simulation_end_us = Time.get_ticks_usec()
		cost_us.append(Time.get_ticks_usec() - begin + flush_cost_us)
		debt_us.append(maxi(0, roundi(begin - first_tick_us - (tick - 1) * STEP_US)))
	elif server and close_tick >= 0 and tick >= close_tick + 12:
		emit_result()
	elif not server and not final_sent:
		if tick <= INPUT_TICKS:
			var move := PackedInt32Array([MOVE, actor, tick, Time.get_ticks_msec(), 0])
			schedule(1, move, tick, actor)
			# Identical retry and out-of-scope actor are separate control fixtures.
			if tick % 17 == 0:
				var retry := move.duplicate()
				retry[4] = 1
				send(1, retry, true)
				send(1, retry, true)
				send(1, PackedInt32Array([MOVE, actor, tick - 1, 0, 1]), true)
			if tick % 31 == 0:
				var other_actor := (actor + 1) % client_count if client_count > 1 else client_count
				send(1, PackedInt32Array([MOVE, other_actor, tick, 0, 1]), true)
		elif tick == INPUT_TICKS + 16:
			send(1, PackedInt32Array([DRAINED]), true)
	flush_cost_us = 0
	return false

func server_receive(id: int, words: PackedInt32Array) -> void:
	if not seats.has(id):
		invalid += 1
		return
	var slot: int = seats[id]
	match words[0]:
		MOVE:
			if words.size() == 5 and words[4] == 0 and words[1] == slot:
				if words[2] < primary_seq[slot]:
					reordered_inputs += 1
				primary_seq[slot] = maxi(primary_seq[slot], words[2])
			if words.size() != 5 or words[2] <= 0 or words[2] > INPUT_TICKS:
				invalid += 1
			elif words[1] != slot:
				unauthorized += 1
			elif words[2] == latest[slot]:
				duplicate += 1
			elif words[2] < latest[slot] or final_sent:
				stale += 1
			else:
				# Audit independently of the authoritative sequence window.
				if seen[id].has(words[2]):
					accepted_duplicate += 1
				seen[id][words[2]] = true
				latest[slot] = words[2]
				echoes[slot] = words[3]
				positions[slot] += 1
				accepted[slot] += 1
		DRAINED:
			drained[id] = true
		ACK:
			if not final_sent or words.size() != 2 or words[1] != (positions.to_byte_array().hex_encode().hash() & 0x7fffffff):
				fail("final snapshot checksum")
				return
			if not acknowledged.has(id):
				final_ack_matches += 1
			acknowledged[id] = true
			if acknowledged.size() == client_count and close_tick < 0:
				close_tick = tick
				for peer_id: int in seats:
					send(peer_id, PackedInt32Array([CLOSE]), true)
		_:
			invalid += 1

func client_receive(words: PackedInt32Array) -> void:
	match words[0]:
		START:
			print("P0_START")
			actor = words[1]
			started = true
		STATE:
			if not started or words.size() != client_count + AI_COUNT + 3:
				fail("snapshot size or ordering")
			elif words[1] <= final_state_tick or final_sent:
				reordered_snapshots += 1
			else:
				final_state_tick = words[1]
				received_state = words.slice(3)
				snapshots += 1
				if words[2] > last_echo_sample:
					last_echo_sample = words[2]
					ack_age_ms.append(Time.get_ticks_msec() - words[2])
		FINAL:
			if words.size() != client_count + AI_COUNT + 2 or words[1] < final_state_tick:
				fail("final snapshot version/size")
				return
			final_state_tick = words[1]
			final_sent = true
			received_state = words.slice(2)
			send(1, PackedInt32Array([ACK, received_state.to_byte_array().hex_encode().hash() & 0x7fffffff]), true)
			net.host.flush()
			# Keep the reliable peer alive until the server has processed the ACK.
		CLOSE:
			if not final_sent:
				fail("close before final")
			else:
				emit_result()
		_:
			fail("unexpected server message")

func emit_result() -> void:
	var result := {"role": "server" if server else "client", "seed": SEED,
		"mode": "fault" if impaired else "loop", "clients": client_count, "actor": actor,
		"process_id": OS.get_process_id(), "engine": Engine.get_version_info().string,
		"sent_app_bytes": sent_bytes, "received_app_bytes": recv_bytes,
		"enet_sent_bytes": net.host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA),
		"enet_received_bytes": net.host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA),
		"scheduled": queued, "dropped": dropped, "reorder_holds": forced_reorders,
		"early_disconnects": early_disconnects}
	if server:
		result.merge({"connected": max_connections, "entities": positions.size(), "final_positions": Array(positions),
			"final_tick": cost_us.size(), "accepted": Array(accepted), "stale": stale, "duplicate": duplicate,
			"unauthorized": unauthorized, "invalid": invalid, "applied_twice": accepted_duplicate, "primary_reordered": reordered_inputs,
			"matching_acks": final_ack_matches, "cost_us": cost_us, "debt_us": debt_us,
			"simulation_wall_ms": (simulation_end_us - first_tick_us) / 1000.0,
			"traffic_window_ms": (Time.get_ticks_usec() - first_tick_us) / 1000.0})
	else:
		result.merge({"final_positions": Array(received_state), "final_tick": final_state_tick,
			"snapshots_applied": snapshots, "old_snapshots": reordered_snapshots, "ack_age_ms": ack_age_ms})
	print("P0_RESULT ", JSON.stringify(result))
	finished = true
	quit(0)
