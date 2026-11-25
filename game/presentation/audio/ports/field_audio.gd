extends Node
## Client-side consumer of the committed EventEnvelope stream for one Mission.
signal subtitle_requested(key: String, event_id: String)
signal important_notice(key: String, event_id: String)

const R = preload("res://contracts/result.gd")
const S = preload("res://contracts/schema.gd")
const Cues = preload("res://presentation/audio/field_cues.gd")
const GROUPS := ["Master","Voice","Effects","Music","Ambience","UI"]
const DEFAULTS := {"master":1.0,"voice":1.0,"effects":0.8,"music":0.65,"ambience":0.6,"ui":0.85,"subtitles":true}
const REPLAY_TICKS := 32
const FADE_SECONDS := 0.35
var _cues := Cues.new()
var _scope := ""
var _generation := 0
var _path := ""
var _mix := DEFAULTS.duplicate()
var _buses := {}
var _pool := []
var _music: Array[AudioStreamPlayer] = []
var _track := "silent"
var _deck := 0
var _fade := 1.0
var _start_gains := [0.0,0.0]
var _seen := {}
var _history := {}
var _latest := -1
var _layer: CanvasLayer
var _caption: Label
var _caption_time := 0.0
var _caption_priority := -1
var _played := 0
var _dropped := 0
var _peak := 0
var _voice_id := ""
var _voice_language := ""
var _speaking := false
static var _tts_owner := 0


func open_scope(scope_id: String, voice_budget: int = 16, settings_path: String = "user://field_audio.cfg") -> Dictionary:
	if not is_inside_tree() or not _scope.is_empty():
		return R.fail("InvalidState","scope")
	if scope_id.is_empty() or voice_budget < 4 or voice_budget > 96 or (not settings_path.is_empty() and not settings_path.begins_with("user://")):
		return R.fail("InvalidArgument","audio_scope")
	var settings := DEFAULTS.duplicate()
	if not settings_path.is_empty() and FileAccess.file_exists(settings_path):
		var config := ConfigFile.new()
		if config.load(settings_path) != OK:
			return R.fail("Unavailable","audio_settings")
		for key in config.get_section_keys("mixer"):
			settings[key] = config.get_value("mixer",key)
	if not _valid_mix(settings):
		return R.fail("InvalidArgument","audio_settings")
	_scope = scope_id
	_generation += 1
	_path = settings_path
	_mix = settings
	_played = 0
	_dropped = 0
	_peak = 0
	if voice_budget >= 5 and ProjectSettings.get_setting_with_override("audio/general/text_to_speech") and DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		_voice_language = TranslationServer.get_locale().get_slice("_",0)
		var voices := DisplayServer.tts_get_voices_for_language(_voice_language)
		if not voices.is_empty():
			_voice_id = voices[0]
	# Private bus names allow two listeners/scopes to coexist with independent settings.
	for category: String in GROUPS:
		var index := AudioServer.bus_count
		AudioServer.add_bus()
		var bus := "Field%s_%s"%[get_instance_id(),category]
		AudioServer.set_bus_name(index,bus)
		AudioServer.set_bus_send(index,"Master" if category=="Master" else _buses.Master)
		_buses[category] = bus
	for i in 2:
		var deck := AudioStreamPlayer.new()
		deck.bus = _buses.Music
		add_child(deck)
		_music.append(deck)
	var nonspatial := 2 if voice_budget >= 6 else 1
	for i in voice_budget-2-int(not _voice_id.is_empty()):
		var spatial := i >= nonspatial
		var player: Variant = AudioStreamPlayer3D.new() if spatial else AudioStreamPlayer.new()
		if spatial:
			player.unit_size = 8.0
		add_child(player)
		_pool.append({"node":player,"spatial":spatial,"busy":false,"score":0,"cue":"","category":""})
		player.finished.connect(_finished.bind(i))
	_layer = CanvasLayer.new()
	_layer.layer = 11
	add_child(_layer)
	_caption = Label.new()
	_layer.add_child(_caption)
	_caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_caption.offset_top = -110
	_caption.offset_bottom = -60
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_font_size_override("font_size",22)
	_caption.add_theme_color_override("font_outline_color",Color.BLACK)
	_caption.add_theme_constant_override("outline_size",5)
	_caption.hide()
	_apply_mix()
	set_process(true)
	return R.ok()


## A mounted HUD may render the same prioritized localized line itself.
func set_hud_captions(active: bool) -> void:
	if is_instance_valid(_layer): _layer.visible = not active

func caption_text() -> String:
	return _caption.text if is_instance_valid(_caption) and _caption.visible else ""

func _valid_mix(settings: Dictionary) -> bool:
	for key in settings:
		if not DEFAULTS.has(key):
			return false
		var value: Variant = settings[key]
		if key == "subtitles":
			if typeof(value) != TYPE_BOOL:
				return false
		elif typeof(value) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(value)) or value < 0 or value > 1:
			return false
	return true


func set_mixer(partial_settings: Dictionary) -> Dictionary:
	if _scope.is_empty():
		return R.fail("InvalidState","scope")
	if not _valid_mix(partial_settings):
		return R.fail("InvalidArgument","mixer")
	var changed := _mix.duplicate()
	changed.merge(partial_settings,true)
	if not _path.is_empty():
		var config := ConfigFile.new()
		for key in changed:
			config.set_value("mixer",key,changed[key])
		var folder := ProjectSettings.globalize_path(_path).get_base_dir()
		if DirAccess.make_dir_recursive_absolute(folder) != OK or config.save(_path) != OK:
			return R.fail("Unavailable","audio_settings")
	_mix = changed
	if _mix.master <= 0 or _mix.voice <= 0:
		_stop_speech()
		for slot: Dictionary in _pool:
			if slot.busy and slot.category == "Voice":
				slot.node.stop()
				slot.busy = false
	if not _mix.subtitles:
		_caption.hide()
		_caption_priority = -1
	_apply_mix()
	return R.ok()


func _apply_mix() -> void:
	var duck: bool = (_speaking or _pool.any(func(s): return s.busy and s.category == "Voice")) and _mix.voice > 0
	for category: String in GROUPS:
		var volume: float = _mix[category.to_lower()]
		var index := AudioServer.get_bus_index(_buses[category])
		var gain := linear_to_db(maxf(volume,0.0001))
		if duck and category in ["Effects","Ambience","Music"]:
			gain -= 9.0
		AudioServer.set_bus_volume_db(index,gain)
		AudioServer.set_bus_mute(index,volume == 0)


func _stop_speech() -> void:
	if _tts_owner == get_instance_id():
		DisplayServer.tts_stop()
		_tts_owner = 0
	_speaking = false


func _finished(index: int) -> void:
	var slot: Dictionary = _pool[index]
	slot.busy = false
	if slot.category == "Voice":
		_apply_mix()


func _claim(spatial: bool, score: int, command: bool) -> int:
	# Two spoken orders in the same listener mix would mask one another.
	if command:
		for i in _pool.size():
			var current: Dictionary = _pool[i]
			if current.busy and current.category == "Voice":
				return i if score >= current.score else -1
	var lowest := -1
	for i in _pool.size():
		var slot: Dictionary = _pool[i]
		if slot.spatial != spatial:
			continue
		if not slot.busy:
			return i
		if lowest == -1 or slot.score < _pool[lowest].score:
			lowest = i
	if lowest >= 0 and (score > _pool[lowest].score or (command and score == _pool[lowest].score)):
		return lowest
	return -1


func _remember(id: String, stamp: int) -> bool:
	if stamp < _latest - REPLAY_TICKS or _seen.has(id):
		return false
	if stamp > _latest:
		_latest = stamp
		for old in _history.keys():
			if old < stamp - REPLAY_TICKS:
				for retired in _history[old]:
					_seen.erase(retired)
				_history.erase(old)
	if not _history.has(stamp):
		_history[stamp] = []
	_history[stamp].append(id)
	_seen[id] = true
	return true


func _subtitle(key: String, event_id: String, priority: int) -> void:
	if not _mix.subtitles:
		return
	if _caption_time <= 0 or priority >= _caption_priority:
		_caption.text = _cues.caption(key)
		_caption.show()
		_caption_priority = priority
		_caption_time = 2.0
	subtitle_requested.emit(key,event_id)


func play_event(event: Dictionary, listener_position: Vector3 = Vector3.ZERO) -> Dictionary:
	if _scope.is_empty() or not is_inside_tree():
		return R.fail("InvalidState","scope")
	var valid := S.validate_shape("EventEnvelope",event)
	if not valid.ok:
		return valid
	if event.scope_id != _scope or not is_same(event.payload.get("confirmed",true),true) or not is_same(event.payload.get("predicted",false),false):
		return R.fail("InvalidState","confirmed_scope")
	if not listener_position.is_finite():
		return R.fail("InvalidArgument","listener")
	var kind: String = event.type
	if not Cues.CUES.has(kind):
		return R.ok({"status":"unmapped"})
	var cue: Array = Cues.CUES[kind]
	var category: String = cue[0]
	var occluded: Variant = event.payload.get("occluded",false)
	if typeof(occluded) != TYPE_BOOL:
		return R.fail("InvalidArgument","occluded")
	var position := listener_position
	if event.payload.has("position_mm"):
		var v: Variant = event.payload.position_mm
		if typeof(v) != TYPE_ARRAY or v.size()!=3 or not v.all(func(n): return typeof(n)==TYPE_INT and absi(n)<=2147483647):
			return R.fail("InvalidArgument","position_mm")
		position = Vector3(v[0],v[1],v[2])*0.001
	var clip := kind
	var key := "audio."+kind
	if kind == "command":
		if typeof(event.payload.get("order_type","command")) != TYPE_STRING:
			return R.fail("InvalidArgument","order_type")
		clip = _cues.spoken(event.payload.get("order_type","command"))
		key = "audio.order."+clip
	var stamp: int = event.revision if event.tick == null else event.tick
	if not _remember(event.event_id,stamp):
		return R.ok({"status":"duplicate_or_stale"})
	if kind in ["victory","defeat"]:
		transition_music(kind)
	var generation := _generation
	if category == "Voice" or kind in ["victory","defeat","routed","regrouped"]:
		important_notice.emit(key,event.event_id)
		if generation != _generation or _scope != event.scope_id:
			return R.ok({"status":"scope_closed"})
	var spatial := category in ["Effects","Ambience"]
	var distance := listener_position.distance_to(position)
	if spatial and distance > float(cue[2]):
		_dropped += 1
		return R.ok({"status":"distance"})
	if _mix.subtitles and (not spatial or int(cue[1]) >= 40 or distance <= 12):
		_subtitle(key,event.event_id,cue[1])
		if generation != _generation or _scope != event.scope_id:
			return R.ok({"status":"scope_closed"})
	if _mix.master <= 0 or _mix[category.to_lower()] <= 0:
		return R.ok({"status":"muted","subtitle_key":key})
	if category == "Music":
		# The crossfade deck already owns the score for this outcome.
		return R.ok({"status":"played","subtitle_key":key})
	var score: int = int(cue[1])*1000 - roundi(distance*8) if spatial else int(cue[1])*1000
	if spatial and occluded:
		score -= 10000
	var which := _claim(spatial,score,category=="Voice")
	if which < 0:
		_dropped += 1
		return R.ok({"status":"budget","subtitle_key":key})
	var slot: Dictionary = _pool[which]
	var player: Variant = slot.node
	var was_voice: bool = slot.busy and slot.category == "Voice"
	player.stop()
	player.bus = _buses[category]
	var device_voice := category == "Voice" and not _voice_id.is_empty() and _voice_language == TranslationServer.get_locale().get_slice("_",0)
	if category == "Voice" and not device_voice:
		_stop_speech()
		player.stream = _cues.recorded_voice(key)
	else:
		player.stream = _cues.clip(clip)
	player.volume_db = -10.0 if spatial and occluded else 0.0
	if spatial:
		player.global_position = position
		player.max_distance = float(cue[2])
	slot.busy = true
	slot.score = score
	slot.cue = clip
	slot.category = category
	player.play()
	if device_voice:
		_tts_owner = get_instance_id()
		_speaking = true
		DisplayServer.tts_speak(_cues.caption(key),_voice_id,roundi(_mix.voice*_mix.master*100),1.0,1.0,0,true)
	_played += 1
	_peak = maxi(_peak,_active_count())
	if was_voice or category=="Voice":
		_apply_mix()
	return R.ok({"status":"played","slot":which,"cue_id":clip,"subtitle_key":key})


func transition_music(state: String) -> Dictionary:
	if _scope.is_empty():
		return R.fail("InvalidState","scope")
	if state != "silent" and not Cues.MELODIES.has(state):
		return R.fail("InvalidArgument","music")
	if state == _track:
		return R.ok()
	for i in 2:
		_start_gains[i] = _music[i].volume_linear if _music[i].playing else 0.0
	if state != "silent":
		_deck = 1-_deck
		var next := _music[_deck]
		next.stop()
		next.stream = _cues.clip(state)
		next.volume_linear = 0.0001
		_start_gains[_deck] = 0.0001
		next.play()
	_track = state
	_fade = 0.0
	_peak = maxi(_peak,_active_count())
	return R.ok()


func _process(delta: float) -> void:
	if _scope.is_empty():
		return
	var speaking := _tts_owner == get_instance_id() and DisplayServer.tts_is_speaking()
	if speaking != _speaking:
		_speaking = speaking
		_apply_mix()
	_caption_time -= delta
	if _caption_time <= 0:
		_caption.hide()
	if _fade >= 1.0:
		return
	_fade = minf(1.0,_fade+delta/FADE_SECONDS)
	for i in 2:
		var dest := 1.0 if i==_deck and _track!="silent" else 0.0
		_music[i].volume_linear = maxf(0.0001,lerpf(_start_gains[i],dest,_fade))
		if _fade == 1 and dest == 0:
			_music[i].stop()


func _active_count() -> int:
	var count := 0
	for slot: Dictionary in _pool:
		count += int(slot.busy)
	for player in _music:
		count += int(player.playing)
	return count + int(_speaking)


func diagnostics() -> Dictionary:
	return {"scope":_scope,"allocated":_pool.size()+_music.size()+int(not _voice_id.is_empty()),"active":_active_count(),"peak":_peak,"played":_played,
		"dropped":_dropped,"track":_track,"settings":_mix.duplicate(),"buses":_buses.duplicate(),
		"voice_available":not _voice_id.is_empty(),"caption":caption_text()}


func stop_scope(scope_id: String) -> Dictionary:
	if scope_id != _scope or _scope.is_empty():
		return R.fail("NotFound","scope")
	_stop_speech()
	_voice_id = ""
	for slot: Dictionary in _pool:
		slot.node.stop()
		slot.node.free()
	for player in _music:
		player.stop()
		player.free()
	_layer.free()
	_pool.clear()
	_music.clear()
	var names := _buses.values()
	names.reverse()
	for bus in names:
		var index := AudioServer.get_bus_index(bus)
		if index > 0:
			AudioServer.remove_bus(index)
	_buses.clear()
	_seen.clear()
	_history.clear()
	_latest = -1
	_track = "silent"
	_fade = 1
	_caption_time = 0
	_caption_priority = -1
	_scope = ""
	set_process(false)
	return R.ok()


func _exit_tree() -> void:
	if not _scope.is_empty():
		stop_scope(_scope)
