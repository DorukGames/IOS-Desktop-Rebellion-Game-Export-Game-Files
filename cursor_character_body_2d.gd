extends CharacterBody2D

# ─────────────────────────────────────────────
#  CURSORCHARACTER.GD  –  Desktop Rebellion
# ─────────────────────────────────────────────

@onready var hp_bar : ProgressBar = $HPProgressBar2

const MAX_HP        := 100.0
var   health        : float = MAX_HP

# ── Touch damage ─────────────────────────────
const RAM_RADIUS    := 40.0    # px from enemy center = touching
const RAM_MIN_SPEED := 100.0   # minimum speed to deal any damage
const RAM_COOLDOWN  := 0.35    # seconds before same enemy can be hit again

# ── Invincibility frames ──────────────────────
const INVINCIBLE_TIME   := 0.5
var   _invincible_timer : float = 0.0

# ── Grab ─────────────────────────────────────
const GRAB_RADIUS    := 40.0
var   _grabbed_enemy : Node = null

# ── Rope ─────────────────────────────────────
var is_tied     : bool = false
var _tie_source : Node = null

# ── Speed ────────────────────────────────────
var _current_speed : float   = 0.0
var _mouse_delta   : Vector2 = Vector2.ZERO   # accumulated delta from InputEventMouseMotion

# ── Internal ─────────────────────────────────
var _ram_cooldowns : Dictionary = {}

signal died


func _ready() -> void:
	add_to_group("cursor")
	# Capture locks real cursor to center and gives us relative delta — like FPS
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hp_bar.max_value = MAX_HP
	hp_bar.value     = MAX_HP
	hp_bar.visible   = GameSettings.show_hp


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		# Accumulate delta — applied in _physics_process
		_mouse_delta += (event as InputEventMouseMotion).relative


func _physics_process(delta: float) -> void:
	# ── Pointer acceleration ─────────────────────
	# Faster mouse movement = disproportionately larger cursor movement
	# mimicking OS pointer acceleration that MOUSE_MODE_CAPTURED strips away
	var raw        : Vector2 = _mouse_delta
	_mouse_delta   = Vector2.ZERO
	var raw_speed  : float   = raw.length()
	# Acceleration curve: slow moves are 1:1, fast moves get boosted
	var accel_mult : float   = 1.0 + (raw_speed * 0.06)
	var move       : Vector2 = raw * accel_mult * (0.15 if is_tied else 1.0)

	_current_speed = move.length() / delta
	_current_speed = minf(_current_speed, 10000.0)

	velocity = (move / delta).limit_length(10000.0)
	move_and_slide()

	# ── Boundary enforcement ─────────────────
	_enforce_boundary()

	# ── Grab input ───────────────────────────
	if Input.is_action_just_pressed("selection_draw"):
		_try_grab()
	if Input.is_action_just_released("selection_draw"):
		_release_grab()

	# ── Carry grabbed enemy ──────────────────
	if _grabbed_enemy != null:
		if is_instance_valid(_grabbed_enemy):
			_grabbed_enemy.global_position = global_position
		else:
			_grabbed_enemy = null

	# ── DAMAGE CASE 1: cursor touches enemy ──
	# Check every enemy, if within RAM_RADIUS and fast enough → damage
	else:
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if _ram_cooldowns.has(enemy):
				continue
			var dist : float = global_position.distance_to(enemy.global_position)
			if dist <= RAM_RADIUS and _current_speed >= RAM_MIN_SPEED:
				var dmg : float = ceilf(_current_speed / 500.0)
				enemy.take_damage(dmg)
				_ram_cooldowns[enemy] = RAM_COOLDOWN

	# ── Tick iframes ──────────────────────────
	if _invincible_timer > 0.0:
		_invincible_timer -= delta

	# ── Tick cooldowns ────────────────────────
	var to_remove : Array = []
	for e in _ram_cooldowns:
		_ram_cooldowns[e] -= delta
		if _ram_cooldowns[e] <= 0.0:
			to_remove.append(e)
	for e in to_remove:
		_ram_cooldowns.erase(e)


# ════════════════ BOUNDARY ═══════════════════════

func _enforce_boundary() -> void:
	var area := get_tree().get_first_node_in_group("allowed_area") as Area2D
	if area == null:
		return
	# Get the CollisionShape2D child directly — its global_position includes any offset
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
	global_position = Vector2(
		clampf(global_position.x, center.x - half.x, center.x + half.x),
		clampf(global_position.y, center.y - half.y, center.y + half.y)
	)


# ════════════════ GRAB ════════════════════════════

func _try_grab() -> void:
	var closest      : Node  = null
	var closest_dist : float = GRAB_RADIUS
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var d : float = global_position.distance_to(enemy.global_position)
		if d <= closest_dist:
			closest_dist = d
			closest      = enemy
	if closest == null:
		return
	_grabbed_enemy = closest
	if _grabbed_enemy.has_method("set_grabbed"):
		_grabbed_enemy.set_grabbed(true)


func _release_grab() -> void:
	if _grabbed_enemy == null:
		return
	if is_instance_valid(_grabbed_enemy):
		if _grabbed_enemy.has_method("set_grabbed"):
			_grabbed_enemy.set_grabbed(false)
		_grabbed_enemy.velocity = velocity
	_grabbed_enemy = null


# ════════════════ DAMAGE API ═════════════════════

func take_hit(amount: float) -> void:
	if _invincible_timer > 0.0:
		return
	health = maxf(health - amount, 0.0)
	hp_bar.value      = health
	_invincible_timer = INVINCIBLE_TIME

	var mesh := get_node_or_null("MeshInstance2D") as MeshInstance2D
	if mesh:
		var tween := create_tween()
		tween.tween_property(mesh, "modulate", Color.RED,   0.06)
		tween.tween_property(mesh, "modulate", Color.WHITE, 0.15)

	if health <= 0.0:
		emit_signal("died")


# ════════════════ ROPE API ═══════════════════════

func tie_rope(source: Node) -> void:
	is_tied     = true
	_tie_source = source

func untie_rope() -> void:
	is_tied     = false
	_tie_source = null

func break_rope_feedback() -> void:
	pass


# ════════════════ UTILITIES ══════════════════════

func get_speed() -> float:
	return _current_speed
