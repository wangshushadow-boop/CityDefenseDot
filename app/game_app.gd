extends Node
## 应用入口，负责菜单、战场和结算切换；业务模块可脱离场景树单独验证。
const RULES: BattleRules = preload("res://data/default_rules.tres")
var ui := BattleUI.new()
var sound := BattleAudio.new()
var mission: BattleMission
var view: BattlefieldView
var aim := Vector2.ZERO
var commanding := false
var gesture := CommanderCombat.Direction.RIGHT
var guard_held := false
var guard_side := CommanderCombat.Direction.RIGHT
var choosing_order := false
var inspect_points := false

func _ready() -> void:
	add_child(ui)
	add_child(sound)
	ui.start_requested.connect(start)
	ui.menu_requested.connect(menu)
	ui.ordered.connect(order)
	ui.action_requested.connect(action)
	ui.resume_requested.connect(set_commanding.bind(false))
	ui.target_selected.connect(select_target)
	ui.menu(BattleSetup.standalone(RULES))

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
	ui.battle(mission)
	gesture = CommanderCombat.Direction.RIGHT
	ui.refresh(mission)
	set_commanding(false)

func set_commanding(value: bool) -> void:
	clear_controls()
	commanding = value
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if value else Input.MOUSE_MODE_CAPTURED
	ui.command_mode(value, not mission.teams[0].leader.alive())

func clear_controls() -> void:
	var leader := mission.teams[0].leader
	leader.manual.cancel(leader)
	guard_held = false
	choosing_order = false
	inspect_points = false
	view.camera.zoom = false
	view.camera.free_look = false
	view.camera.free_yaw = 0
	view.camera.free_pitch = 0
	ui.toggle_score(false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and mission and mission.result.is_empty():
		set_commanding(true)

func _physics_process(dt: float) -> void:
	if not mission or not mission.result.is_empty():
		return
	var axis := Vector2(int(Input.is_physical_key_pressed(KEY_D)) - int(Input.is_physical_key_pressed(KEY_A)),
		int(Input.is_physical_key_pressed(KEY_S)) - int(Input.is_physical_key_pressed(KEY_W)))
	var leader := mission.teams[0].leader
	view.camera.track_target(leader, mission.field)
	leader.manual.facing = Vector2.from_angle(view.camera.yaw)
	if guard_held and not leader.guarding:
		leader.manual.defend(leader, guard_side, true)
	mission.tick(dt, Vector2.ZERO if commanding else view.camera.movement(axis))
	if mission.result.is_empty():
		var was_overview := view.camera.overview
		view.refresh(aim, dt)
		if view.camera.overview and not was_overview:
			set_commanding(true)
		view.marker.visible = commanding
		if choosing_order:
			var ground: Variant = order_ground()
			view.marker.visible = ground != null
			if ground != null:
				view.place_marker(ground)
		for caption in view.captions:
			caption.visible = commanding or inspect_points
		ui.update_reticle(leader, gesture, choosing_order, commanding)
		ui.refresh(mission)

func _input(event: InputEvent) -> void:
	if not mission or not mission.result.is_empty():
		return
	var leader := mission.teams[0].leader
	if event is InputEventKey:
		var key: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		if not event.echo and handle_key(key, event.pressed, leader):
			get_viewport().set_input_as_handled()
	elif ui.score.visible and event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		if event.pressed:
			ui.report_scroll.scroll_vertical += -40 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 40
		get_viewport().set_input_as_handled()
	elif not commanding and leader.alive():
		if event is InputEventMouseMotion:
			var delta: Vector2 = event.relative
			view.camera.orbit(delta)
			leader.manual.facing = Vector2.from_angle(view.camera.yaw)
			if not view.camera.free_look and delta.length_squared() >= 1.0:
				gesture = CommanderCombat.mouse_direction(delta)
		elif event is InputEventMouseButton:
			match event.button_index:
				MOUSE_BUTTON_LEFT:
					if choosing_order and event.pressed:
						keyboard_order(BattleFormation.Order.HOLD)
					elif event.pressed:
						leader.manual.ready_attack(leader, gesture)
					else:
						leader.manual.release(leader)
				MOUSE_BUTTON_RIGHT:
					guard_held = event.pressed
					guard_side = gesture
					leader.manual.defend(leader, gesture, guard_held)
				MOUSE_BUTTON_MIDDLE:
					if event.pressed:
						view.camera.locked = leader.manual.front_target(leader, mission.field, 18, 0.70) if view.camera.locked == null else null
				MOUSE_BUTTON_WHEEL_UP:
					if event.pressed:
						leader.manual.drawn = true
				MOUSE_BUTTON_WHEEL_DOWN:
					if event.pressed and leader.manual.shield_hp > 0:
						leader.manual.shield = not leader.manual.shield
						leader.manual.cancel(leader)
			get_viewport().set_input_as_handled()

func handle_key(key: Key, pressed: bool, leader: BattleAgent) -> bool:
	if key == KEY_TAB:
		ui.toggle_score(pressed)
		return true
	if key in [KEY_BACKSPACE, KEY_ESCAPE] and pressed:
		if choosing_order:
			choosing_order = false
			ui.notify_order("")
		else:
			set_commanding(not commanding or not leader.alive())
		return true
	if key in [KEY_0, KEY_1, KEY_2, KEY_3] and pressed:
		if key != KEY_0:
			var role: String = ["field", "bow", "guard"][key - KEY_1]
			var found := false
			for i in mission.teams[0].groups.size():
				if mission.teams[0].groups[i].role == role:
					ui.picker.select(i)
					found = true
					break
			if not found:
				ui.notify_order("本次出战名单没有该编队")
				return true
		else:
			ui.picker.select(mission.teams[0].groups.size())
		ui.notify_order("已选%s · F1 下达移动军令" % selected_name())
		return true
	if pressed and choosing_order and key in [KEY_F1, KEY_F2, KEY_F3]:
		keyboard_order([BattleFormation.Order.HOLD, BattleFormation.Order.FOLLOW, BattleFormation.Order.CHARGE][key - KEY_F1])
		return true
	if pressed and key == KEY_F1:
		choosing_order = true
		leader.manual.cancel(leader)
		ui.notify_order("")
		return true
	if commanding or not leader.alive():
		return false
	match key:
		KEY_SHIFT: view.camera.zoom = pressed
		KEY_QUOTELEFT, KEY_MINUS:
			view.camera.free_look = pressed
			if not pressed:
				view.camera.free_yaw = 0
				view.camera.free_pitch = 0
		KEY_ALT: inspect_points = pressed
		_: return pressed and foot_action(key, leader)
	return true

func foot_action(key: Key, leader: BattleAgent) -> bool:
	match key:
		KEY_SPACE: leader.manual.jump()
		KEY_Z:
			if leader.manual.elevation == 0 and leader.manual.vertical_speed == 0:
				leader.manual.crouching = not leader.manual.crouching
		KEY_CAPSLOCK: leader.manual.walking = not leader.manual.walking
		KEY_E: leader.manual.kick(leader, mission.field)
		KEY_R: view.camera.first_person = not view.camera.first_person
		KEY_BACKSLASH:
			if leader.manual.swing_time <= 0:
				leader.manual.cancel(leader)
				leader.manual.drawn = not leader.manual.drawn
		KEY_KP_ADD: view.camera.distance = maxf(1.5, view.camera.distance - 0.4)
		KEY_KP_SUBTRACT: view.camera.distance = minf(6, view.camera.distance + 0.4)
		KEY_F:
			var facility := mission.nearby_facility()
			if facility.is_empty():
				ui.notify_order("附近没有可操作的设施")
			else:
				action(facility)
		_: return false
	return true

func selected_name() -> String:
	return ui.picker.get_item_text(ui.picker.selected)

func order_ground() -> Variant:
	var screen := get_viewport().get_mouse_position() if commanding else get_viewport().get_visible_rect().size * 0.5
	return view.camera.ground_point(screen)

func keyboard_order(code: BattleFormation.Order) -> void:
	var at := aim
	if code == BattleFormation.Order.HOLD:
		var ground: Variant = order_ground()
		if ground == null:
			ui.notify_order("请对准战场地面，再按 F1 定位")
			return
		at = ground
	aim = at
	ui.field_map.aim = at
	issue_order(code, code == BattleFormation.Order.CHARGE)

func _unhandled_input(event: InputEvent) -> void:
	if not mission or not mission.result.is_empty() or not commanding:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var point = view.camera.ground_point(event.position)
		if point is Vector2:
			select_target(point)
		elif choosing_order:
			ui.notify_order("请对准战场地面或点击沙盘定位")

func select_target(at: Vector2) -> void:
	aim = at
	ui.field_map.aim = at
	ui.field_map.queue_redraw()
	if choosing_order:
		issue_order(BattleFormation.Order.HOLD, false)
	else:
		ui.notify_order("目标已选定，可下达坚守或冲锋")

func order(code: BattleFormation.Order) -> void:
	if not mission or not mission.result.is_empty():
		return
	issue_order(code, false)

func issue_order(code: BattleFormation.Order, pursue: bool) -> void:
	var groups := mission.teams[0].groups
	for i in groups.size():
		if ui.picker.selected == groups.size() or ui.picker.selected == i:
			mission.command(i, code, aim, pursue)
	choosing_order = false
	ui.notify_order("%s · %s" % [selected_name(), BattleFormation.LABELS[code]])
	if not sound.playing:
		sound.play()

func action(key: String) -> void:
	if not mission or not mission.result.is_empty():
		return
	var message := mission.player_action(key)
	if mission.result.is_empty():
		ui.notify_order(message)

func show_result(result: Dictionary) -> void:
	clear_controls()
	sound.stop()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ui.summary(result)

func menu() -> void:
	view.queue_free()
	view = null
	mission = null
	ui.menu(BattleSetup.standalone(RULES))

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if mission:
		mission.release_targets()
