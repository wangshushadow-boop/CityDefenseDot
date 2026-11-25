extends SceneTree
const Audio = preload("res://presentation/audio/ports/field_audio.gd")
var errors := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		errors+=1
		printerr("FAIL ",label)
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var audio := Audio.new()
	root.add_child(audio)
	var opened := audio.open_scope("handoff",4,"")
	check(opened.ok,"open audio")
	check(audio.set_mixer({"master":0}).ok,"muted accessibility settings")
	TranslationServer.set_locale("zh")
	var ev := {"scope_id":"handoff","revision":1,"tick":1,"type":"command","event_id":"order","payload":{"confirmed":true,"order_type":"hold"}}
	check(audio.play_event(ev,Vector3.ZERO).ok,"confirmed voice")
	var layer: CanvasLayer = audio.find_children("*","CanvasLayer",false,false)[0]
	check(layer.visible and audio.caption_text()=="坚守阵地！","standalone subtitle")
	audio.set_hud_captions(true)
	check(not layer.visible and audio.caption_text()=="坚守阵地！","HUD owns single visible caption")
	audio.set_hud_captions(false)
	check(layer.visible,"restore standalone caption")
	check(audio.set_mixer({"subtitles":false}).ok and audio.caption_text().is_empty(),"subtitle option")
	audio.stop_scope("handoff")
	check(audio.caption_text().is_empty(),"no text after scope release")
	audio.free()
	await create_timer(0.15).timeout
	print("AUDIO_HANDOFF errors=",errors)
	quit(int(errors>0))
