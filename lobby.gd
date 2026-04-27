extends Control

# ─────────────────────────────────────────────
#  LOBBY.GD  –  Desktop Rebellion
#  Handles the start screen:
#    • ExitButtonCheckBox  – show exit button in-game
#    • HpShowCheckBox      – show HP bar in-game
#    • PlayButton          – launch main scene
#    • ExitButton          – quit the app
# ─────────────────────────────────────────────

@onready var exit_btn_checkbox : CheckBox = $Panel/ExitButtonCheckBox
@onready var hp_show_checkbox  : CheckBox = $Panel/HpShowCheckBox
@onready var play_button       : Button   = $Panel/PlayButton
@onready var exit_button       : Button   = $Panel/ExitButton

const MAIN_SCENE := "res://main.tscn"


# ════════════════════════════════════════════════
func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	exit_button.pressed.connect(_on_exit_pressed)

	# Load saved preferences if they exist
	exit_btn_checkbox.button_pressed = GameSettings.show_exit_button
	hp_show_checkbox.button_pressed  = GameSettings.show_hp

	# Live-save as user toggles
	exit_btn_checkbox.toggled.connect(_on_exit_checkbox_toggled)
	hp_show_checkbox.toggled.connect(_on_hp_checkbox_toggled)


# ════════════════════════════════════════════════

func _on_play_pressed() -> void:
	# Save latest checkbox state before switching scenes
	GameSettings.show_exit_button = exit_btn_checkbox.button_pressed
	GameSettings.show_hp          = hp_show_checkbox.button_pressed
	get_tree().change_scene_to_file(MAIN_SCENE)


func _on_exit_pressed() -> void:
	get_tree().quit()


func _on_exit_checkbox_toggled(pressed: bool) -> void:
	GameSettings.show_exit_button = pressed


func _on_hp_checkbox_toggled(pressed: bool) -> void:
	GameSettings.show_hp = pressed
