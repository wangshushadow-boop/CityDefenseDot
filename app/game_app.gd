extends Node
## 应用入口，负责菜单、战场和结算切换；业务模块可脱离场景树单独验证。
const RULES: BattleRules = preload("res://data/default_rules.tres")
var ui := BattleUI.new()
var sound := BattleAudio.new()
var mission: BattleMission
var view: BattlefieldView
var aim := Vector2.ZERO
var commanding := false

func _ready() -> void:
	add_child(ui)
	add_child(sound)
	ui.start_requested.connect(start)
	ui.menu_requested.connect(menu)
	ui.ordered.connect(order)
	ui.action_requested.connect(action)
	ui.menu()

func start(guards: int) -> void:
	open_battle(BattleSetup.standalone(RULES, guards))

func open_battle(setup: BattleSetup) -> void:
	if mission != null:
		return
	var error := setup.validation_error()
	if not error.is_empty():
		push_error(error)
		return
	mission = BattleMission.new(setup, RULES)
	mission.finished.connect(show_result)
	view = BattlefieldView.new()
	add_child(view)
	view.build(mission)
	aim = BattleSpace.GRAIN
	ui.battle(mission.teams[0])
	ui.refresh(mission)
	set_commanding(false)

func set_commanding(value: bool) -> void:
	commanding = value
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if value else Input.MOUSE_MODE_CAPTURED
	ui.command_mode(value)

func _physics_process(dt: float) -> void:
	if not mission or not mission.result.is_empty():
		return
	var axis := Vector2(int(Input.is_physical_key_pressed(KEY_D)) - int(Input.is_physical_key_pressed(KEY_A)),
		int(Input.is_physical_key_pressed(KEY_S)) - int(Input.is_physical_key_pressed(KEY_W)))
	var attack := Input.is_physical_key_pressed(KEY_SPACE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var block := Input.is_physical_key_pressed(KEY_SHIFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	mission.tick(dt, view.camera.movement(axis), attack and not commanding, block and not commanding)
	if mission.result.is_empty():
		view.refresh(aim, dt)
		if view.camera.overview and not commanding:
			set_commanding(true)
		ui.refresh(mission)

func _input(event: InputEvent) -> void:
	if not mission or not mission.result.is_empty():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_TAB, KEY_ESCAPE]:
		set_commanding(not commanding or not mission.teams[0].leader.alive())
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and not commanding:
		view.camera.orbit(event.relative)

func _unhandled_input(event: InputEvent) -> void:
	if not mission or not mission.result.is_empty() or not commanding:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var point = view.camera.ground_point(event.position)
		if point is Vector2:
			aim = point
			ui.feedback.text = "目标已选定，可下达坚守或冲锋"

func order(code: BattleFormation.Order) -> void:
	if not mission or not mission.result.is_empty():
		return
	mission.command(ui.picker.selected, code, aim)
	ui.feedback.text = "军令已下达 · " + BattleFormation.LABELS[code]
	sound.play()

func action(key: String) -> void:
	if not mission or not mission.result.is_empty():
		return
	var message := mission.player_action(key)
	if mission.result.is_empty():
		ui.feedback.text = message

func show_result(result: Dictionary) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ui.summary(result)

func menu() -> void:
	view.queue_free()
	view = null
	mission = null
	ui.menu()

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if mission:
		mission.release_targets()
