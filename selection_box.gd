extends StaticBody2D

# ─────────────────────────────────────────────
#  SELECTIONBOX.GD  –  Desktop Rebellion
#  Left-click + drag to draw a selection box.
#  The box has real collision — enemies caught
#  inside or hit by its edges take damage.
#  Bigger box drawn faster = more damage.
# ─────────────────────────────────────────────

@onready var panel     : Panel          = $Panel
@onready var col_shape : CollisionShape2D = $CollisionShape2D

# ── Settings ─────────────────────────────────
const MIN_SIZE          := 20.0     # px — smaller than this won't spawn
const DAMAGE_SIZE_SCALE := 0.08    # damage += size_area * scale
const DAMAGE_SPEED_SCALE:= 0.04   # damage += draw_speed * scale
const BASE_DAMAGE       := 8.0
const HOLD_TIME         := 0.6     # seconds box stays solid after release
const FADE_TIME         := 0.25    # fade-out duration

# ── State ─────────────────────────────────────
var _drawing     : bool    = false
var _start_pos   : Vector2 = Vector2.ZERO
var _draw_speed  : float   = 0.0   # px/s while dragging
var _prev_mouse  : Vector2 = Vector2.ZERO
var _hold_timer  : float   = 0.0
var _fading      : bool    = false
var _active      : bool    = false   # box is solid and can deal damage
var _hit_enemies : Array   = []      # prevent double-hitting same enemy


# ════════════════════════════════════════════════
func _ready() -> void:
	visible = false
	_set_box_size(Vector2.ZERO, Vector2.ZERO)


func _process(delta: float) -> void:
	var mouse : Vector2 = get_global_mouse_position()

	# ── Drawing phase ─────────────────────────
	if Input.is_action_just_pressed("selection_draw"):
		_start_draw(mouse)

	if _drawing:
		# Track draw speed
		_draw_speed = mouse.distance_to(_prev_mouse) / delta
		_prev_mouse = mouse
		_update_box(_start_pos, mouse)

	if Input.is_action_just_released("selection_draw") and _drawing:
		_release_draw(mouse)

	# ── Hold phase ────────────────────────────
	if _active and not _drawing:
		_hold_timer -= delta
		if _hold_timer <= 0.0:
			_start_fade()

	# ── Fade phase ────────────────────────────
	if _fading:
		var t := 1.0 - (_hold_timer / -FADE_TIME)
		modulate.a = lerpf(1.0, 0.0, t)
		_hold_timer -= delta
		if _hold_timer <= -FADE_TIME:
			_reset()


# ════════════════════════════════════════════════

func _start_draw(mouse: Vector2) -> void:
	_drawing    = true
	_start_pos  = mouse
	_prev_mouse = mouse
	_draw_speed = 0.0
	_hit_enemies.clear()
	visible     = true
	modulate.a  = 1.0
	_active     = false
	_fading     = false


func _update_box(from: Vector2, to: Vector2) -> void:
	var rect := Rect2(from, to - from).abs()
	_apply_rect(rect)


func _release_draw(mouse: Vector2) -> void:
	_drawing = false
	var rect := Rect2(_start_pos, mouse - _start_pos).abs()

	if rect.size.x < MIN_SIZE or rect.size.y < MIN_SIZE:
		_reset()
		return

	_apply_rect(rect)
	_active     = true
	_hold_timer = HOLD_TIME

	# Damage all enemies overlapping right now
	_check_overlap_damage(rect)


func _apply_rect(rect: Rect2) -> void:
	# Position panel
	panel.global_position = rect.position
	panel.size            = rect.size

	# Resize collision shape (RectangleShape2D)
	var shape := col_shape.shape as RectangleShape2D
	if shape == null:
		shape = RectangleShape2D.new()
		col_shape.shape = shape
	shape.size            = rect.size
	col_shape.global_position = rect.get_center()


func _check_overlap_damage(rect: Rect2) -> void:
	# Find all enemies in the scene and check AABB overlap
	var area   : float = rect.size.x * rect.size.y
	var damage : float = BASE_DAMAGE + area * DAMAGE_SIZE_SCALE + _draw_speed * DAMAGE_SPEED_SCALE

	for enemy in get_tree().get_nodes_in_group("enemies"):
		if _hit_enemies.has(enemy):
			continue
		var enemy_pos : Vector2 = enemy.global_position
		if rect.has_point(enemy_pos):
			enemy.take_damage(damage)
			_hit_enemies.append(enemy)
			_spawn_explosion(enemy_pos)


func _spawn_explosion(pos: Vector2) -> void:
	var exp_scene := load("res://explosion.tscn") as PackedScene
	if exp_scene == null:
		return
	var exp := exp_scene.instantiate() as Node2D
	get_parent().add_child(exp)
	exp.global_position = pos


func _start_fade() -> void:
	_fading     = true
	_active     = false
	_hold_timer = 0.0
	# Disable collision during fade
	col_shape.disabled = true


func _reset() -> void:
	visible            = false
	_drawing           = false
	_active            = false
	_fading            = false
	col_shape.disabled = false
	modulate.a         = 1.0


func _set_box_size(pos: Vector2, sz: Vector2) -> void:
	panel.global_position = pos
	panel.size            = sz
