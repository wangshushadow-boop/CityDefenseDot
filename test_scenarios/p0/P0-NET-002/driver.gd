extends SceneTree

const Base := preload("res://probe.gd")
const History := preload("res://server.gd")
var peers: Array[ENetMultiplayerPeer] = []
var states: Array[Dictionary] = []
var target_count := 0
var closed := 0
var failed := false

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	target_count = args[2].to_int()
	Engine.max_fps = 144
	for i in target_count:
		var peer := ENetMultiplayerPeer.new()
		var err := peer.create_client("127.0.0.1", args[1].to_int())
		if err != OK:
			fail("create_client %d %s" % [i, error_string(err)])
			return
		peers.append(peer)
		states.append({"seat": -1, "tick": 0, "state_tick": -1, "snapshots": 0, "final_tick": -1,
			"checksum": 0, "closed": false, "sent": 0, "received": 0})

func fail(reason: String) -> void:
	failed = true
	printerr("P0_FAILURE ", reason)
	quit(1)

func send(i: int, words: PackedInt32Array, reliable: bool) -> void:
	var peer := peers[i]
	peer.set_target_peer(1)
	peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE
	var bytes := words.to_byte_array()
	if peer.put_packet(bytes) != OK:
		fail("put_packet")
	states[i].sent += bytes.size()

func receive(i: int, words: PackedInt32Array) -> void:
	var s := states[i]
	match words[0]:
		Base.START:
			s.seat = words[1]
		Base.STATE:
			if words.size() != target_count + Base.AI_COUNT + 3:
				fail("invalid snapshot")
			elif words[1] > s.state_tick:
				s.state_tick = words[1]
				s.applied = words.slice(3)
				s.snapshots += 1
		History.PROMPT:
			var trial := words[3]
			var mapped := words[2]
			if trial == 5:
				mapped += 30
			elif trial == 8:
				mapped -= 1
			var action := PackedInt32Array([History.ACTION, words[1], mapped, int(trial == 3)])
			send(i, action, true)
			if trial == 6:
				send(i, action, true)
		Base.FINAL:
			var values := words.slice(2)
			if values.size() != target_count + Base.AI_COUNT or words[1] < s.state_tick:
				fail("invalid final")
				return
			s.final_tick = words[1]
			s.applied = values
			s.checksum = values.to_byte_array().hex_encode().hash() & 0x7fffffff
			# SHA-256 over the entire applied vector is checked independently by Python.
			var h := HashingContext.new()
			h.start(HashingContext.HASH_SHA256)
			h.update(s.applied.to_byte_array())
			s.digest = h.finish().hex_encode()
			send(i, PackedInt32Array([Base.ACK, s.checksum]), true)
		Base.CLOSE:
			if s.final_tick < 0 or s.closed:
				fail("close without final, or duplicate")
			else:
				s.closed = true
				s.erase("applied")
				closed += 1
		_:
			fail("unexpected packet")

func _physics_process(_delta: float) -> bool:
	if failed:
		return false
	if Time.get_ticks_msec() > 15000:
		fail("driver timeout %d/%d" % [closed, target_count])
		return false
	for i in peers.size():
		var peer := peers[i]
		var s := states[i]
		peer.poll()
		while peer.get_available_packet_count() > 0:
			var bytes := peer.get_packet()
			s.received += bytes.size()
			receive(i, bytes.to_int32_array())
		if s.seat < 0 or s.final_tick >= 0:
			continue
		s.tick += 1
		if s.tick <= Base.INPUT_TICKS:
			var move := PackedInt32Array([Base.MOVE, s.seat, s.tick, Time.get_ticks_msec(), 0])
			send(i, move, false)
			if s.tick == 60:
				send(i, move, true)
				send(i, move, true)
				send(i, PackedInt32Array([Base.MOVE, s.seat, s.tick - 1, 0, 1]), true)
				send(i, PackedInt32Array([Base.MOVE, (int(s.seat) + 1) % target_count, s.tick, 0, 1]), true)
		elif s.tick == Base.INPUT_TICKS + 16:
			send(i, PackedInt32Array([Base.DRAINED]), true)
	if closed == target_count:
		var ids: Array[int] = []
		for peer in peers:
			ids.append(peer.get_unique_id())
		print("P0_DRIVER ", JSON.stringify({"pid": OS.get_process_id(), "peer_ids": ids, "seats": states}))
		quit(0)
	return false
