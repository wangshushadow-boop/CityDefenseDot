extends SceneTree
## Standalone probe; an independent project.godot with config_version=5 suffices.

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var wav := AudioStreamWAV.new()
	wav.mix_rate = 16000
	var samples := PackedByteArray()
	samples.resize(16000)
	for i in samples.size():
		samples[i] = roundi(48 * sin(TAU * 440 * i / wav.mix_rate)) & 255
	wav.data = samples
	var capture: AudioEffectCapture
	if "--pcm" in args or "--drain" in args:
		capture = AudioEffectCapture.new()
		capture.buffer_length = 1.0
		AudioServer.add_bus_effect(0,capture)
	var player := AudioStreamPlayer.new()
	root.add_child(player)
	player.stream = wav
	player.play()
	var playback_ref: WeakRef = weakref(player.get_stream_playback())
	var stream_ref: WeakRef = weakref(wav)
	wav = null
	var peak := 0.0
	if "--pcm" in args:
		await create_timer(0.12,true,false,true).timeout
		var output := capture.get_buffer(capture.get_frames_available())
		for frame in output:
			peak = maxf(peak,absf(frame.x))
		print("PCM frames=",output.size()," peak=",peak)
	var mix_start := capture.get_pushed_frames() if capture else 0
	var started := Time.get_ticks_usec()
	player.stop()
	player.free()
	if "--drain" in args:
		while playback_ref.get_ref() != null and Time.get_ticks_usec()-started < 250000:
			await process_frame
	await process_frame
	var mixed := capture.get_pushed_frames()-mix_start if capture else 0
	if capture:
		AudioServer.remove_bus_effect(0,0)
	print("AUDIO_BACKEND display=",DisplayServer.get_name()," audio=",AudioServer.get_driver_name(),
		" output=",AudioServer.get_output_device()," drain=","--drain" in args,
		" stream_alive=",stream_ref.get_ref()!=null," playback_alive=",playback_ref.get_ref()!=null,
		" elapsed_ms=",(Time.get_ticks_usec()-started)*0.001," post_stop_mix_frames=",mixed)
	var failed := ("--pcm" in args and peak < 0.01) or ("--drain" in args and playback_ref.get_ref()!=null)
	quit(1 if failed else 0)
