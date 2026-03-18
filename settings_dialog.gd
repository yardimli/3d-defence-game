extends Window

# Emitted when a setting is changed by the user.
signal setting_changed(setting_name: String, new_value: Variant)
# NEW: Emitted when the user applies new preview settings.
signal preview_settings_changed(settings: Dictionary)

# --- Node-Referenzen ---
@onready var stacking_checkbox: CheckBox = %StackingCheckbox
# MODIFIED: Renamed button for clarity.
@onready var close_button: Button = %CloseButton
# NEW: References for new UI controls.
@onready var apply_button: Button = %ApplyButton
@onready var model_scale_spinbox: SpinBox = %ModelScaleSpinBox
@onready var cam_pos_x_spinbox: SpinBox = %CamPosXSpinBox
@onready var cam_pos_y_spinbox: SpinBox = %CamPosYSpinBox
@onready var cam_pos_z_spinbox: SpinBox = %CamPosZSpinBox
@onready var look_at_x_spinbox: SpinBox = %LookAtXSpinBox
@onready var look_at_y_spinbox: SpinBox = %LookAtYSpinBox
@onready var look_at_z_spinbox: SpinBox = %LookAtZSpinBox


func _ready():
	# NEW: Make the window modal, which blocks input to the main scene when visible.
	exclusive = true
	
	# Connect UI signals to their handlers.
	stacking_checkbox.toggled.connect(_on_stacking_checkbox_toggled)
	close_button.pressed.connect(hide)
	# NEW: Connect the apply button's signal.
	apply_button.pressed.connect(_on_apply_pressed)
	close_requested.connect(hide)

# Public method to open the dialog and set the initial state of its controls.
func open_with_settings(current_settings: Dictionary):
	# Set the checkbox state based on the current setting from the level editor.
	var allow_stacking = current_settings.get("allow_same_asset_stacking", false)
	stacking_checkbox.button_pressed = allow_stacking
	
	# NEW: Populate the new preview override fields.
	model_scale_spinbox.value = current_settings.get("model_scale", 1.0)
	
	var cam_pos: Vector3 = current_settings.get("position", Vector3(0, 1.0, 2.5))
	cam_pos_x_spinbox.value = cam_pos.x
	cam_pos_y_spinbox.value = cam_pos.y
	cam_pos_z_spinbox.value = cam_pos.z
	
	var look_at: Vector3 = current_settings.get("look_at", Vector3.ZERO)
	look_at_x_spinbox.value = look_at.x
	look_at_y_spinbox.value = look_at.y
	look_at_z_spinbox.value = look_at.z
	
	popup_centered()

# Called when the checkbox is toggled by the user.
func _on_stacking_checkbox_toggled(is_checked: bool):
	# Emit a signal to notify the level editor of the change.
	emit_signal("setting_changed", "allow_same_asset_stacking", is_checked)

# NEW: Called when the "Apply" button is pressed.
func _on_apply_pressed():
	# Gather all the override values from the UI.
	var override_settings = {
		"model_scale": model_scale_spinbox.value,
		"position": Vector3(cam_pos_x_spinbox.value, cam_pos_y_spinbox.value, cam_pos_z_spinbox.value),
		"look_at": Vector3(look_at_x_spinbox.value, look_at_y_spinbox.value, look_at_z_spinbox.value)
	}
	# Emit the signal to send the data to the level editor.
	emit_signal("preview_settings_changed", override_settings)
