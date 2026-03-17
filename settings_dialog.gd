# settings_dialog.gd
extends Window

# Emitted when a setting is changed by the user.
signal setting_changed(setting_name: String, new_value: Variant)

# --- Node-Referenzen ---
@onready var stacking_checkbox: CheckBox = %StackingCheckbox
@onready var close_button: Button = %CloseButton

func _ready():
	# Connect UI signals to their handlers.
	stacking_checkbox.toggled.connect(_on_stacking_checkbox_toggled)
	close_button.pressed.connect(hide)
	close_requested.connect(hide)

# Public method to open the dialog and set the initial state of its controls.
func open_with_settings(current_settings: Dictionary):
	# Set the checkbox state based on the current setting from the level editor.
	var allow_stacking = current_settings.get("allow_same_asset_stacking", false)
	stacking_checkbox.button_pressed = allow_stacking
	
	popup_centered()

# Called when the checkbox is toggled by the user.
func _on_stacking_checkbox_toggled(is_checked: bool):
	# Emit a signal to notify the level editor of the change.
	emit_signal("setting_changed", "allow_same_asset_stacking", is_checked)
