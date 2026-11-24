extends SceneTree

const Audio = preload("res://presentation/audio/ports/field_audio.gd")
const Cues = preload("res://presentation/audio/field_cues.gd")
const SCOPE := "recorded-command-voice"
var errors := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		printerr("FAIL ", label)
		errors += 1

func envelope(kind: String, cue: String, tick: int) -> Dictionary:
	return {"scope_id":SCOPE, "tick":tick, "revision":tick, "event_id":"voice-%d"%tick,
		"type":kind, "payload":{"order_type":cue} if kind=="command" else {}}

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var audio := Audio.new()
	root.add_child(audio)
	# A four-source scope uses two music decks, one flat, and one spatial source.
	check(audio.open_scope(SCOPE,4,"").ok,"bounded scope opened")
	var digest_set := {}
	var tick := 0
	for locale in ["zh_CN","en_US"]:
		TranslationServer.set_locale(locale)
		var dict: Dictionary = Cues.TEXT.get_meta(locale.get_slice("_",0))
		var capture := AudioEffectCapture.new()
		var bus := AudioServer.get_bus_index(audio.diagnostics().buses.Voice)
		AudioServer.add_bus_effect(bus,capture)
		for key: String in dict:
			if not key.begins_with("audio.order.") and key!="audio.warning":
				continue
			tick += 1
			var cue := key.get_slice(".",2) if key!="audio.warning" else "warning"
			var kind := "warning" if cue=="warning" else "command"
			var event := envelope(kind,cue,tick)
			var receipt := audio.play_event(event)
			# A warning has lower priority. Let a pending order finish before admitting it.
			if kind=="warning" and receipt.ok and receipt.value.status=="budget":
				var voice: AudioStreamPlayer = active_voice(audio)
				check(voice!=null,"higher priority order still playing")
				# Keep the player and its two-second, higher-priority subtitle visible.
				await create_timer(2.1).timeout
				tick+=1
				receipt = audio.play_event(envelope(kind,cue,tick))
			check(receipt.ok and receipt.value.status=="played",locale+" played "+key)
			if not receipt.ok or receipt.value.status!="played":
				continue
			check(receipt.value.subtitle_key==key and audio.diagnostics().caption==dict[key],locale+" subtitle "+key)
			var player := active_voice(audio)
			check(player!=null,"normal Voice slot is playing")
			if player==null: continue
			var stream := player.stream as AudioStreamWAV
			check(stream!=null and stream.format==AudioStreamWAV.FORMAT_16_BITS and stream.mix_rate==22050 and stream.get_length()>.25,"recorded waveform "+key)
			if stream==null: continue
			var h := HashingContext.new()
			h.start(HashingContext.HASH_SHA256)
			h.update(stream.data)
			var digest := h.finish().hex_encode()
			check(not digest_set.has(digest),"distinct spoken phrase "+locale+" "+key)
			digest_set[digest] = true
		await create_timer(0.17).timeout
		var samples := capture.get_buffer(capture.get_frames_available())
		var peak := 0.0
		for frame in samples:
			peak = maxf(peak,absf(frame.x))
		check(samples.size()>100 and peak>.005,"real localized voice bus output")
		print("RECORDED_VOICE ",locale," pcm_frames=",samples.size()," peak=",peak)
		AudioServer.remove_bus_effect(bus,0)
	check(digest_set.size()==48,"every bilingual order and warning has unique speech")
	var peak_sources: int = audio.diagnostics().peak
	check(peak_sources<=4 and audio.set_mixer({"voice":0.0}).ok and active_voice(audio)==null,"muting cancels ongoing command")
	check(audio.stop_scope(SCOPE).ok and audio.get_child_count()==0,"scope released")
	audio.free()
	await create_timer(0.15).timeout
	print("RECORDED_VOICES ", "PASS" if errors==0 else "FAIL"," samples=",digest_set.size()," peak_sources=",peak_sources," errors=",errors)
	quit(0 if errors==0 else 1)

func active_voice(audio: Node) -> AudioStreamPlayer:
	var bus: String = audio.diagnostics().buses.Voice
	for node: AudioStreamPlayer in audio.find_children("*","AudioStreamPlayer",false,false):
		if node.bus==bus and node.playing:
			return node
	return null
