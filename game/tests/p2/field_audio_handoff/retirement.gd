extends "res://tests/p2/field_audio_handoff/run.gd"

func command(audio: Audio, id: String) -> Dictionary:
	return audio.play_event({"scope_id":"field","revision":1,"tick":1,"type":"command",
		"event_id":id,"payload":{"confirmed":true,"order_type":"hold"}})

func run() -> void:
	var audio := Audio.new()
	root.add_child(audio)
	check(audio.open_scope("field",4,"").ok,"open")
	check(audio.active_playbacks().is_empty(),"observing idle nodes starts no playback")
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 1.0
	AudioServer.add_bus_effect(0,capture)
	check(audio.transition_music("battle").ok and command(audio,"first").value.status == "played","music and recorded speech playing")
	await create_timer(0.35,true,false,true).timeout
	var mixed := capture.get_buffer(capture.get_frames_available())
	var peak := 0.0
	for sample in mixed:
		peak = maxf(peak,absf(sample.x))
	check(peak > 0.005,"real audio reaches Master")
	check(command(audio,"second").value.status == "played","preempt previous speech")
	check(audio.set_mixer({"voice":0}).ok,"stop second speech just before release")
	var refs := audio.active_playbacks()
	check(refs.size() == 3,"observe music and both retiring voices")
	check(refs == audio.active_playbacks(),"observation is read-only")
	var start_frame := capture.get_pushed_frames()
	var started := Time.get_ticks_usec()
	audio.stop_scope("field")
	audio.free()
	while refs.any(func(ref): return ref.get_ref()!=null) and Time.get_ticks_usec()-started < 250000:
		await process_frame
	var elapsed := (Time.get_ticks_usec()-started)*0.001
	var live := refs.filter(func(ref): return ref.get_ref()!=null).size()
	check(live == 0,"retired before 250 ms")
	print("AUDIO_RETIREMENT driver=",AudioServer.get_driver_name()," refs=",refs.size()," live=",live,
		" elapsed_ms=",elapsed," mixed_after_stop=",capture.get_pushed_frames()-start_frame,
		" pcm_frames=",mixed.size()," pcm_peak=",peak," errors=",errors)
	AudioServer.remove_bus_effect(0,0)
	quit(int(errors>0))
