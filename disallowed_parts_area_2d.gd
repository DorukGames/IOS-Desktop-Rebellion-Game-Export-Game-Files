extends Area2D

# ─────────────────────────────────────────────
#  DISALLOWEDPARTSAREA2D.GD  –  Desktop Rebellion
# ─────────────────────────────────────────────

func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if not (body is CharacterBody2D):
		return

	var spawner := get_tree().get_first_node_in_group("spawner") as Node2D
	if spawner == null:
		spawner = get_node_or_null("/root/Control/Spawner") as Node2D
	if spawner == null:
		push_warning("DisallowedPartsArea2D: Spawner not found!")
		return

	var cb := body as CharacterBody2D
	cb.global_position = spawner.global_position
	cb.velocity        = Vector2.ZERO

	# If it's the enemy, reset AI and give immunity so it doesn't run straight back
	if cb.has_method("_enter_state"):
		cb.call("_enter_state", 0)   # 0 = State.IDLE
	if cb.get("_is_grabbed") != null:
		cb.set("_is_grabbed", false)
	if cb.get("_teleport_immunity") != null:
		cb.set("_teleport_immunity", 0.5)   # 0.5s of standing still after teleport
