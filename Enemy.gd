extends CharacterBody2D

# ─────────────────────────────────────────────
#  ENEMY.GD  –  Desktop Rebellion
# ─────────────────────────────────────────────

@onready var mesh   : MeshInstance2D = $MeshInstance2D
@onready var hp_bar : ProgressBar    = $HPProgressBar

var cursor_node : CharacterBody2D

# ── Movement ─────────────────────────────────
const WALK_SPEED  := 110.0
const DODGE_SPEED := 300.0
const JUMP_FORCE  := -520.0
const GRAVITY     := 900.0
const ACCEL       := 600.0

# ── State machine ─────────────────────────────
enum State { IDLE, WALK, DODGE, THROW, ROPE, COMBO, STUNNED }
var state       : State = State.IDLE
var state_timer : float = 0.0

# ── Cooldowns ────────────────────────────────
var dodge_cd        : float = 0.0
var dodge_check_cd  : float = 2.0   # 50% dodge roll every 2s when close
const DODGE_DIST    := 100.0        # 1m ~ 100px — close range threshold
var throw_cd : float = 0.0          # start ready to throw
var rope_cd  : float = 5.0
var combo_cd : float = 3.0

# ── Rope vars ────────────────────────────────
var rope_line      : Line2D
var rope_extending : bool    = false
var rope_tip       : Vector2 = Vector2.ZERO
const ROPE_EXTEND_SPEED := 350.0
const ROPE_TIE_RADIUS   := 28.0
const ROPE_BREAK_SPEED  := 550.0
const ROPE_HOLD_TIME    := 4.0
var   rope_hold_timer   : float = 0.0

# ── Health & damage state ─────────────────────
var health          : float = 100.0
const HIT_STUN_TIME := 0.5    # freeze duration on hit
var _hit_stun       : float = 0.0
var _is_invincible  : bool  = false

# ── Wall slam ─────────────────────────────────
const SLAM_SPEED_THRESHOLD := 500.0
const SLAM_FREEZE_TIME     := 0.75
var   _slam_frozen         : float   = 0.0
var   _pre_velocity        : Vector2 = Vector2.ZERO

# ── Grabbed ───────────────────────────────────
var _is_grabbed       : bool  = false
var _teleport_immunity: float = 0.0   # brief pause after being teleported

# ── Combo ─────────────────────────────────────
var _combo_step      : int   = 0
var _combo_timer     : float = 0.0
var _combo_sequence  : Array = []   # filled when entering COMBO state

# ── Enrage ────────────────────────────────────
const ENRAGE_HP_THRESHOLD      := 75.0
const SUPER_ANGRY_HP_THRESHOLD := 50.0
var _enraged           : bool  = false
var _super_angry       : bool  = false
var _proj_speed_mult   : float = 1.0
var _enrage_attack_cd  : float = 0.0

signal died(enemy)


# ════════════════════════════════════════════════
func _ready() -> void:
	add_to_group("enemies")   # CRITICAL — must be in this group for cursor to find us
	# Make sure AllowedArea2D is in the allowed_area group (set in editor or here)
	var area := get_tree().get_first_node_in_group("allowed_area")
	if area == null:
		var a := get_node_or_null("/root/Control/AllowedArea2D")
		if a != null:
			a.add_to_group("allowed_area")
	motion_mode  = CharacterBody2D.MOTION_MODE_GROUNDED
	up_direction = Vector2.UP
	_build_rope_line()
	hp_bar.max_value = health
	hp_bar.value     = health
	hp_bar.visible   = GameSettings.show_hp
	_enter_state(State.IDLE)


func _build_rope_line() -> void:
	rope_line = Line2D.new()
	rope_line.width          = 5.0
	rope_line.default_color  = Color(0.50, 0.30, 0.10)
	rope_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	rope_line.end_cap_mode   = Line2D.LINE_CAP_ROUND
	rope_line.visible        = false
	rope_line.add_point(Vector2.ZERO)
	rope_line.add_point(Vector2.ZERO)
	add_child(rope_line)


# ════════════════════════════════════════════════
func _physics_process(delta: float) -> void:
	if cursor_node == null:
		cursor_node = get_tree().get_first_node_in_group("cursor")
		return

	# ── Grabbed — full control by cursor ─────
	if _is_grabbed:
		return

	# ── Teleport immunity — stand still briefly after being teleported
	if _teleport_immunity > 0.0:
		_teleport_immunity -= delta
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# ── Hit stun — frozen, no damage, but CAN still attack
	if _hit_stun > 0.0:
		_hit_stun         -= delta
		_enrage_attack_cd -= delta
		velocity           = Vector2.ZERO
		move_and_slide()
		# Still fire enrage attacks while stunned
		var attack_interval : float = 0.6 if _super_angry else 1.0
		if (_enraged or _super_angry) and _enrage_attack_cd <= 0.0:
			_enrage_attack_cd = attack_interval
			_do_enrage_attack(cursor_node.global_position)
		return

	if not is_on_floor():
		velocity.y += GRAVITY * delta

	# ── Slam freeze ──────────────────────────
	if _slam_frozen > 0.0:
		_slam_frozen -= delta
		velocity = Vector2.ZERO
		move_and_slide()
		return

	state_timer      -= delta
	dodge_cd         -= delta
	dodge_check_cd   -= delta
	throw_cd         -= delta
	rope_cd          -= delta
	combo_cd         -= delta
	_enrage_attack_cd -= delta

	# Check enrage threshold
	if not _enraged and health < ENRAGE_HP_THRESHOLD:
		_enraged = true
		_enrage_attack_cd = 1.0
		if mesh:
			mesh.modulate = Color(1.0, 0.4, 0.0)   # orange tint when enraged

	var cursor_pos : Vector2 = cursor_node.global_position
	var dist       : float   = global_position.distance_to(cursor_pos)

	# Enrage forced attack every second
	if _enraged and _enrage_attack_cd <= 0.0:
		_enrage_attack_cd = 1.0
		_do_enrage_attack(cursor_pos)

	match state:
		State.IDLE  : _state_idle(delta, cursor_pos, dist)
		State.WALK  : _state_walk(delta, cursor_pos, dist)
		State.DODGE : _state_dodge(delta, cursor_pos)
		State.THROW : _state_throw(delta, cursor_pos)
		State.ROPE  : _state_rope(delta, cursor_pos)
		State.COMBO : _state_combo(delta, cursor_pos)

	_pre_velocity = velocity
	move_and_slide()
	_check_wall_slam()
	_enforce_boundary()


# ════════════════ STATE HANDLERS ════════════════

func _state_idle(delta: float, _c: Vector2, _d: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, ACCEL * delta)
	if state_timer <= 0.0:
		_enter_state(State.WALK)


func _state_walk(delta: float, cursor_pos: Vector2, dist: float) -> void:
	var dir : float = sign(cursor_pos.x - global_position.x)
	velocity.x = move_toward(velocity.x, dir * WALK_SPEED, ACCEL * delta)

	# ── Close range dodge logic ──────────────
	if dist <= DODGE_DIST:
		# Immediate dodge if cooldown ready
		if dodge_cd <= 0.0:
			_enter_state(State.DODGE)
			return
		# Every 2 seconds, 50% chance to dodge
		if dodge_check_cd <= 0.0:
			dodge_check_cd = 2.0
			if randf() < 0.5:
				_enter_state(State.DODGE)
				return

	if state_timer <= 0.0:
		_pick_next_action(dist)


func _state_dodge(delta: float, cursor_pos: Vector2) -> void:
	if is_on_floor() and state_timer > 0.4:
		var away : float = -sign(cursor_pos.x - global_position.x)
		velocity.x = away * DODGE_SPEED
		velocity.y = JUMP_FORCE

	if state_timer <= 0.0 and is_on_floor():
		dodge_cd = randf_range(1.2, 3.0)   # shorter cooldown = more dodging
		_enter_state(State.WALK)


func _state_throw(delta: float, cursor_pos: Vector2) -> void:
	velocity.x = move_toward(velocity.x, 0.0, ACCEL * delta)
	if state_timer <= 0.0:
		_spawn_projectile(cursor_pos, false)   # normal = falling
		throw_cd = randf_range(0.8, 2.0)
		_enter_state(State.WALK)


func _state_rope(delta: float, cursor_pos: Vector2) -> void:
	velocity.x = move_toward(velocity.x, 0.0, ACCEL * delta)

	if not rope_extending and not cursor_node.is_tied:
		rope_extending    = true
		rope_tip          = global_position
		rope_line.visible = true

	if rope_extending and not cursor_node.is_tied:
		var dir : Vector2 = (cursor_pos - rope_tip).normalized()
		rope_tip += dir * ROPE_EXTEND_SPEED * delta
		rope_line.set_point_position(0, Vector2.ZERO)
		rope_line.set_point_position(1, rope_tip - global_position)
		if rope_tip.distance_to(cursor_pos) <= ROPE_TIE_RADIUS:
			cursor_node.tie_rope(self)
			rope_hold_timer = ROPE_HOLD_TIME

	elif cursor_node.is_tied:
		rope_line.set_point_position(1, cursor_pos - global_position)
		rope_hold_timer -= delta
		var should_break : bool = false
		if cursor_node.get_speed() > ROPE_BREAK_SPEED:
			should_break = true
			cursor_node.break_rope_feedback()
		if rope_hold_timer <= 0.0:
			should_break = true
		if should_break:
			_end_rope()

	if state_timer <= 0.0:
		_end_rope()


func _end_rope() -> void:
	rope_line.visible = false
	rope_extending    = false
	if cursor_node != null and cursor_node.is_tied:
		cursor_node.untie_rope()
	rope_cd = randf_range(6.0, 12.0)
	_enter_state(State.WALK)


# ════════════════ COMBO STATE ════════════════════
# Sequence format: { "type": "throw"/"rope"/"dodge", "delay": float }

func _state_combo(delta: float, cursor_pos: Vector2) -> void:
	velocity.x = move_toward(velocity.x, 0.0, ACCEL * delta)
	_combo_timer -= delta

	if _combo_timer > 0.0:
		return

	if _combo_step >= _combo_sequence.size():
		combo_cd = 3.0
		_enter_state(State.WALK)
		return

	var step : Dictionary = _combo_sequence[_combo_step]
	_combo_step += 1

	match step["type"]:
		"throw":
			_spawn_projectile(cursor_pos, false)
		"throw_deadly":
			_spawn_projectile(cursor_pos, true)
		"rope":
			# Quick rope lunge — just extend instantly for combo feel
			if not cursor_node.is_tied:
				cursor_node.tie_rope(self)
				rope_line.visible = true
				rope_line.set_point_position(0, Vector2.ZERO)
				rope_line.set_point_position(1, cursor_pos - global_position)
				rope_hold_timer = 2.0
		"dodge":
			var away : float = -sign(cursor_pos.x - global_position.x)
			velocity.x = away * DODGE_SPEED
			velocity.y = JUMP_FORCE

	_combo_timer = step.get("delay", 0.2)


func _start_combo_triple_throw(cursor_pos: Vector2) -> void:
	_combo_sequence = [
		{ "type": "throw", "delay": 0.2 },
		{ "type": "throw", "delay": 0.2 },
		{ "type": "throw", "delay": 0.2 },
	]
	_combo_step  = 0
	_combo_timer = 0.0
	_enter_state(State.COMBO)


func _start_combo_rope_then_throw(cursor_pos: Vector2) -> void:
	_combo_sequence = [
		{ "type": "rope",  "delay": 0.8 },   # tie first
		{ "type": "throw", "delay": 0.2 },   # then throw while tied
		{ "type": "throw", "delay": 0.2 },
	]
	_combo_step  = 0
	_combo_timer = 0.0
	_enter_state(State.COMBO)


func _start_combo_dodge_throw(cursor_pos: Vector2) -> void:
	_combo_sequence = [
		{ "type": "dodge", "delay": 0.5 },
		{ "type": "throw", "delay": 0.2 },
		{ "type": "throw", "delay": 0.3 },
	]
	_combo_step  = 0
	_combo_timer = 0.0
	_enter_state(State.COMBO)


# ════════════════ STATE TRANSITIONS ══════════════

func _enter_state(new_state: State) -> void:
	state = new_state
	match new_state:
		State.IDLE  : state_timer = randf_range(0.6, 1.2)
		State.WALK  : state_timer = randf_range(1.5, 3.0)
		State.DODGE : state_timer = 0.9
		State.THROW : state_timer = 0.6
		State.ROPE  : state_timer = ROPE_HOLD_TIME + 1.5
		State.COMBO : state_timer = 999.0   # combo manages itself


func _pick_next_action(dist: float) -> void:
	var cursor_pos : Vector2 = cursor_node.global_position if cursor_node else global_position

	# Combo every 3 seconds — always pick one if in range
	if combo_cd <= 0.0 and dist < 600.0:
		var roll : int = randi() % 3
		match roll:
			0: _start_combo_triple_throw(cursor_pos)
			1: _start_combo_rope_then_throw(cursor_pos)
			2: _start_combo_dodge_throw(cursor_pos)
		return

	# Throw very frequently — 70% chance when cooldown ready
	if throw_cd <= 0.0 and dist < 600.0 and randf() < 0.7:
		_enter_state(State.THROW)
		return

	if rope_cd <= 0.0 and dist < 400.0 and randf() < 0.5:
		_enter_state(State.ROPE)
		return

	# Only idle 10% of the time — mostly keep walking/attacking
	if randf() < 0.1:
		_enter_state(State.IDLE)
	else:
		_enter_state(State.WALK)


# ════════════════ BOUNDARY ═══════════════════════

func _enforce_boundary() -> void:
	var area := get_tree().get_first_node_in_group("allowed_area") as Area2D
	if area == null:
		return
	var col_shape : CollisionShape2D = null
	for child in area.get_children():
		if child is CollisionShape2D:
			col_shape = child as CollisionShape2D
			break
	if col_shape == null:
		return
	var rect_shape := col_shape.shape as RectangleShape2D
	if rect_shape == null:
		return
	var half   : Vector2 = rect_shape.size / 2.0
	var center : Vector2 = col_shape.global_position
	var clamped : Vector2 = Vector2(
		clampf(global_position.x, center.x - half.x, center.x + half.x),
		clampf(global_position.y, center.y - half.y, center.y + half.y)
	)
	if clamped != global_position:
		global_position = clamped
		velocity        = Vector2.ZERO


# ════════════════ GRAB API ═══════════════════════

func set_grabbed(grabbed: bool) -> void:
	_is_grabbed = grabbed
	if grabbed:
		velocity          = Vector2.ZERO
		rope_line.visible = false
		if cursor_node != null and cursor_node.is_tied:
			cursor_node.untie_rope()
	# On release, velocity is set by cursor fling


# ════════════════ WALL SLAM ══════════════════════

func _check_wall_slam() -> void:
	if _slam_frozen > 0.0:
		return
	var speed_before : float = _pre_velocity.length()
	var speed_after  : float = velocity.length()
	# DAMAGE CASE 2: enemy hits wall fast → take damage based on speed
	if speed_before >= SLAM_SPEED_THRESHOLD and speed_after < speed_before * 0.3:
		var dmg : float = ceilf(speed_before / 100.0)
		take_damage(dmg)
		_slam_frozen = SLAM_FREEZE_TIME
		_spawn_explosion(global_position)


# ════════════════ EXPLOSION ══════════════════════

func _spawn_explosion(pos: Vector2) -> void:
	var exp_scene := load("res://explosion.tscn") as PackedScene
	if exp_scene == null:
		return
	var exp := exp_scene.instantiate() as Node2D
	get_parent().add_child(exp)
	exp.global_position = pos


# ════════════════ PROJECTILE ═════════════════════

func _spawn_projectile(cursor_pos: Vector2, deadly: bool = false) -> void:
	var proj_scene := load("res://Projectile.tscn") as PackedScene
	if proj_scene == null:
		push_warning("Enemy: res://Projectile.tscn not found")
		return
	var spawn_pos : Vector2 = global_position + Vector2(0.0, -20.0)
	var dir       : Vector2 = (cursor_pos - spawn_pos).normalized()
	var proj      := proj_scene.instantiate() as Node2D
	get_parent().add_child(proj)
	proj.global_position = spawn_pos
	proj.call("launch", dir, 650.0 * _proj_speed_mult, 18.0, deadly)


# ════════════════ ENRAGE ATTACKS ═════════════════

func _do_enrage_attack(cursor_pos: Vector2) -> void:
	var roll : float = randf()
	if roll < 0.75:
		_start_combo_triple_deadly(cursor_pos)    # 75% triple deadly combo
	else:
		_spawn_projectile_fast(cursor_pos)        # 25% single fast deadly


func _spawn_projectile_fast(cursor_pos: Vector2) -> void:
	var proj_scene := load("res://Projectile.tscn") as PackedScene
	if proj_scene == null:
		return
	var spawn_pos : Vector2 = global_position + Vector2(0.0, -20.0)
	var dir       : Vector2 = (cursor_pos - spawn_pos).normalized()
	var proj      := proj_scene.instantiate() as Node2D
	get_parent().add_child(proj)
	proj.global_position = spawn_pos
	# Single deadly box gets 2x speed on top of the multiplier
	proj.call("launch", dir, 650.0 * _proj_speed_mult * 2.0, 18.0, true)


func _start_combo_triple_deadly(cursor_pos: Vector2) -> void:
	# 3 deadly boxes with 0.2s between — no gravity, go straight
	_combo_sequence = [
		{ "type": "throw_deadly", "delay": 0.2 },
		{ "type": "throw_deadly", "delay": 0.2 },
		{ "type": "throw_deadly", "delay": 0.2 },
	]
	_combo_step  = 0
	_combo_timer = 0.0
	_enter_state(State.COMBO)


# ════════════════ DAMAGE ═════════════════════════

func take_damage(amount: float) -> void:
	if _is_invincible or _hit_stun > 0.0:
		return

	health = maxf(health - amount, 0.0)
	hp_bar.value = health

	# Hit stun — freeze + flash + invincible for 0.5s
	_hit_stun      = HIT_STUN_TIME
	_is_invincible = true

	if mesh:
		var tween := create_tween()
		var base_color : Color = Color(1.0, 0.4, 0.0) if _enraged else Color.WHITE
		# Flash bright then fade to semi-transparent during stun
		tween.tween_property(mesh, "modulate", Color(1, 1, 1, 0.3), 0.05)
		tween.tween_interval(HIT_STUN_TIME - 0.1)
		# Return to enrage color (orange) or normal (white)
		tween.tween_property(mesh, "modulate", base_color, 0.1)
		tween.tween_callback(func(): _is_invincible = false)

	if health <= 0.0:
		_die()


func _die() -> void:
	emit_signal("died", self)
	queue_free()
