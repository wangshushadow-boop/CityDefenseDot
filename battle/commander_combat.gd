class_name CommanderCombat extends RefCounted
## 统领的徒步动作。按下锁定来向，松开才挥击；挥空、击门和命中共用恢复时间。
enum Direction { LEFT, RIGHT, OVERHEAD, THRUST }
const SWING_DURATION := 0.29
const CONTACT_TIME := 0.10
const CROUCH_DROP := 0.32
var direction := Direction.RIGHT
var winding := false
var held := 0.0
var swing_time := 0.0
var kick_time := 0.0
var bashing := false
var walking := false
var crouching := false
var elevation := 0.0
var vertical_speed := 0.0
var drawn := true
var shield := true
var shield_hp := 100.0
var facing := Vector2.RIGHT

static func mouse_direction(delta: Vector2) -> Direction:
	if absf(delta.x) > absf(delta.y):
		return Direction.RIGHT if delta.x > 0 else Direction.LEFT
	return Direction.THRUST if delta.y > 0 else Direction.OVERHEAD

func ready_attack(unit: BattleAgent, side: Direction) -> void:
	if not unit.alive() or not drawn or unit.cooldown > 0 or unit.guarding or winding:
		return
	direction = side
	held = 0
	winding = true

func defend(unit: BattleAgent, side: Direction, pressed: bool) -> void:
	if pressed and swing_time <= 0 and kick_time <= 0:
		winding = false
		direction = side
	unit.guarding = pressed and unit.alive() and (drawn or shield) and swing_time <= 0 and kick_time <= 0

func cancel(unit: BattleAgent) -> void:
	winding = false
	unit.guarding = false

func tick(unit: BattleAgent, field: BattleSpace, dt: float) -> void:
	if winding:
		held += dt
	var previous := swing_time
	swing_time = maxf(0, previous - dt)
	# 挥到身前才按当时的位置结算；跨过接触时刻的长帧也只命中一次。
	if previous > SWING_DURATION - CONTACT_TIME and swing_time <= SWING_DURATION - CONTACT_TIME:
		hit(unit, field)
	kick_time = maxf(0, kick_time - dt)
	if elevation > 0 or vertical_speed > 0:
		vertical_speed -= 13.0 * dt
		elevation = maxf(0, elevation + vertical_speed * dt)
		if elevation == 0:
			vertical_speed = 0

func jump() -> void:
	if elevation == 0 and vertical_speed == 0 and kick_time == 0:
		crouching = false
		vertical_speed = 4.3

func movement_scale(axis: Vector2) -> float:
	var speed := 1.0
	if crouching or walking:
		speed = 0.43 if crouching else 0.54
	elif axis.dot(facing) < -0.2:
		speed = 0.68
	if kick_time > 0:
		return 0
	return speed * (0.82 if winding else 1.0)

func front_target(unit: BattleAgent, field: BattleSpace, reach: float, min_dot: float, sweep_from := 0.0) -> BattleAgent:
	var best: BattleAgent
	var best_score := INF
	for enemy in field.near(unit.position, reach, 1 - unit.side):
		var offset := enemy.position - unit.position
		if offset.length_squared() > 0.0001 and facing.dot(offset.normalized()) < min_dot:
			continue
		# 横斩先掠过起手侧，等距敌人分立两侧时可用鼠标选择先击中谁。
		var score := offset.length() - sweep_from * facing.cross(offset)
		if score < best_score and field.clear_line(unit.position, enemy.position):
			best = enemy
			best_score = score
	return best

func release(unit: BattleAgent) -> void:
	if not winding:
		return
	winding = false
	if not unit.alive() or unit.cooldown > 0:
		return
	unit.cooldown = unit.spec.interval
	swing_time = SWING_DURATION

func hit(unit: BattleAgent, field: BattleSpace) -> void:
	var narrow := direction == Direction.THRUST or direction == Direction.OVERHEAD
	var sweep_from := 0.0
	if not narrow:
		sweep_from = 0.55 if direction == Direction.RIGHT else -0.55
	var enemy := front_target(unit, field, unit.spec.reach, 0.78 if narrow else 0.38, sweep_from)
	if enemy != null:
		enemy.receive_hit(unit.spec.damage * lerpf(0.65, 1.0, clampf(held / 0.38, 0, 1)))
	else:
		var gate := field.forts[1 - unit.side].gate - unit.position
		if facing.dot(gate.normalized()) > 0.38 and gate.length() < 2:
			field.forts[1 - unit.side].damage_gate(2)

func kick(unit: BattleAgent, field: BattleSpace) -> void:
	if not unit.alive() or unit.cooldown > 0 or elevation > 0:
		return
	bashing = unit.guarding and shield
	cancel(unit)
	kick_time = 0.36
	unit.cooldown = 0.85
	var enemy := front_target(unit, field, 1.05, 0.62)
	if enemy != null:
		enemy.receive_hit(2)
		enemy.stagger = 0.55
		enemy.windup = -1
		field.move(enemy, enemy.position + facing * 0.45, 0.15, false)

static func parry_side(incoming: Direction) -> Direction:
	if incoming == Direction.RIGHT:
		return Direction.LEFT
	if incoming == Direction.LEFT:
		return Direction.RIGHT
	return incoming

func absorb(unit: BattleAgent, damage: float, source: BattleAgent, incoming: Direction) -> float:
	if not unit.guarding or facing.dot((source.position - unit.position).normalized()) < 0.25:
		return damage
	# 对面从其右侧挥来，防守者向左接招。盾牌错向仍可挡住正面伤害，但磨损更大。
	var correct := direction == parry_side(incoming)
	if shield:
		shield_hp = maxf(0, shield_hp - damage * (0.15 if correct else 0.55))
		shield = shield_hp > 0
		unit.guarding = shield or drawn
		return 0
	return 0.0 if drawn and correct and not source.spec.ranged else damage
