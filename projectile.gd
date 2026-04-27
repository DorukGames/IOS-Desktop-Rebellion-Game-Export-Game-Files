extends Area2D

# ─────────────────────────────────────────────
#  PROJECTILE.GD  –  Desktop Rebellion
#  Thrown by enemies at the cursor.
#  Always spawns an explosion on impact.
# ─────────────────────────────────────────────

const BASE_SPEED   := 650.0
const GRAVITY      := 600.0
const BASE_DAMAGE  := 18.0
const LIFETIME     := 4.5
const SPIN_SPEED   := 240.0

var _velocity  : Vector2 = Vector2.ZERO
var _damage    : float   = BASE_DAMAGE
var _lifetime  : float   = LIFETIME
var _deadly    : bool    = false   # if true: no gravity, goes straight

@onready var mesh = $MeshInstance2D


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func launch(direction: Vector2, speed: float = BASE_SPEED, damage: float = BASE_DAMAGE, deadly: bool = false) -> void:
	_velocity = direction.normalized() * speed
	_damage   = damage
	_deadly   = deadly


func _physics_process(delta: float) -> void:
	if not _deadly:
		_velocity.y += GRAVITY * delta
	global_position += _velocity * delta

	if mesh:
		mesh.rotation_degrees += SPIN_SPEED * delta

	_lifetime -= delta
	if _lifetime <= 0.0:
		_spawn_explosion()
		queue_free()


func _on_body_entered(body: Node) -> void:
	_spawn_explosion()

	if body.is_in_group("cursor"):
		if body.has_method("take_hit"):
			body.take_hit(_damage)

	queue_free()


func _spawn_explosion() -> void:
	var exp_scene := load("res://explosion.tscn") as PackedScene
	if exp_scene == null:
		return
	var exp := exp_scene.instantiate() as Node2D
	# Add to parent so it outlives the projectile
	get_parent().add_child(exp)
	exp.global_position = global_position
