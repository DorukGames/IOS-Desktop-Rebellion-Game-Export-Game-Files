extends Control

# ─────────────────────────────────────────────
#  MAIN.GD  –  Desktop Rebellion
# ─────────────────────────────────────────────

@onready var exit_button        : Button          = $ExitButton
@onready var cursor             : CharacterBody2D = $CursorCharacterBody2D
@onready var enemy              : CharacterBody2D = $Enemy
@onready var speed_label        : Label           = $SpeedLabel
@onready var enemy_status_label : Label           = $EnemyStatusLabel

@onready var endings            : Control         = $ENDINGS
@onready var lose_screen        : Control         = $ENDINGS/Lose
@onready var win_screen         : Control         = $ENDINGS/Win

@onready var cursor_hp          : ProgressBar     = $CursorCharacterBody2D/HPProgressBar2
@onready var enemy_hp           : ProgressBar     = $Enemy/HPProgressBar

@onready var lose_exit_button    : Button = $ENDINGS/Lose/Panel/ExitButton
@onready var lose_restart_button : Button = $ENDINGS/Lose/Panel/RestartButton
@onready var win_exit_button     : Button = $ENDINGS/Win/Panel/ExitButton
@onready var win_restart_button  : Button = $ENDINGS/Win/Panel/RestartButton

var _game_active : bool = true
var _enemy_alive : bool = true
var _ending_shown : bool = false


func _ready() -> void:
	exit_button.visible = GameSettings.show_exit_button

	if not exit_button.pressed.is_connected(_on_exit_pressed):
		exit_button.pressed.connect(_on_exit_pressed)

	if is_instance_valid(cursor):
		if not cursor.died.is_connected(_on_player_died):
			cursor.died.connect(_on_player_died)

	if is_instance_valid(enemy):
		enemy.cursor_node = cursor
		_connect_enemy(enemy)
		_enemy_alive = true
	else:
		_enemy_alive = false

	_update_enemy_status_label()

	endings.visible = false
	lose_screen.visible = false
	win_screen.visible = false
	endings.z_index = 9999

	if not lose_exit_button.pressed.is_connected(_on_exit_pressed):
		lose_exit_button.pressed.connect(_on_exit_pressed)
	if not win_exit_button.pressed.is_connected(_on_exit_pressed):
		win_exit_button.pressed.connect(_on_exit_pressed)

	if not lose_restart_button.pressed.is_connected(_on_restart_pressed):
		lose_restart_button.pressed.connect(_on_restart_pressed)
	if not win_restart_button.pressed.is_connected(_on_restart_pressed):
		win_restart_button.pressed.connect(_on_restart_pressed)


func _connect_enemy(target_enemy: CharacterBody2D) -> void:
	if target_enemy == null:
		return

	if target_enemy.has_signal("died"):
		if not target_enemy.died.is_connected(_on_enemy_died):
			target_enemy.died.connect(_on_enemy_died)

	if not target_enemy.tree_exited.is_connected(_on_enemy_tree_exited):
		target_enemy.tree_exited.connect(_on_enemy_tree_exited)


func _process(_delta: float) -> void:
	if _game_active and is_instance_valid(cursor):
		var spd : float = cursor.get_speed()
		speed_label.text = "speed : %d" % int(spd)

	# Fallback: if enemy vanished without died signal, still win
	if _game_active and _enemy_alive:
		if not is_instance_valid(enemy):
			_trigger_win()

	_update_enemy_status_label()


func _update_enemy_status_label() -> void:
	if not is_instance_valid(enemy_status_label):
		return

	if _enemy_alive:
		enemy_status_label.text = "Status: Alive"
	else:
		enemy_status_label.text = "Status: Dead"


func _show_ending(target_screen: Control) -> void:
	if _ending_shown:
		return

	_ending_shown = true
	_game_active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	speed_label.visible = false
	exit_button.visible = false

	if is_instance_valid(cursor_hp):
		cursor_hp.visible = false
	if is_instance_valid(enemy_hp):
		enemy_hp.visible = false

	endings.visible = true
	lose_screen.visible = (target_screen == lose_screen)
	win_screen.visible = (target_screen == win_screen)


# ════════════════ LOSE ═══════════════════════

func _on_player_died() -> void:
	if not _game_active or _ending_shown:
		return

	_show_ending(lose_screen)

	if is_instance_valid(cursor):
		cursor.call_deferred("queue_free")


# ════════════════ WIN ════════════════════════

func _trigger_win() -> void:
	if not _game_active or _ending_shown:
		return

	_enemy_alive = false
	_update_enemy_status_label()
	_show_ending(win_screen)

	if is_instance_valid(enemy):
		enemy.call_deferred("queue_free")

	if is_instance_valid(cursor):
		cursor.call_deferred("queue_free")


func _on_enemy_died() -> void:
	_trigger_win()


func _on_enemy_tree_exited() -> void:
	# If enemy got removed for any reason, count it as win
	_trigger_win()


# ════════════════ RESPAWN ════════════════════

func _respawn_enemy() -> void:
	var spawn_node : Node2D = get_node_or_null("Spawner") as Node2D
	if spawn_node == null:
		spawn_node = get_node_or_null("spawner") as Node2D

	if spawn_node == null:
		push_warning("Main: spawner/Spawner node not found")
		return

	var enemy_scene := load("res://Enemy.tscn") as PackedScene
	if enemy_scene == null:
		push_warning("Main: res://Enemy.tscn not found")
		return

	var new_enemy := enemy_scene.instantiate() as CharacterBody2D
	add_child(new_enemy)
	new_enemy.global_position = spawn_node.global_position
	new_enemy.cursor_node = cursor

	enemy = new_enemy
	_enemy_alive = true
	_connect_enemy(enemy)
	_update_enemy_status_label()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			if _game_active:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_exit_pressed() -> void:
	get_tree().quit()


func _on_restart_pressed() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().reload_current_scene()
