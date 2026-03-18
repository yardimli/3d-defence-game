extends Window

# Emitted when the user clicks the "Update Sun" button.
# The dictionary contains the new position, rotation, and energy of the sun.
signal sun_updated(settings: Dictionary)

# --- Node-Referenzen ---
@onready var sun_pos_x_edit: LineEdit = %SunPosXEdit
@onready var sun_pos_y_edit: LineEdit = %SunPosYEdit
@onready var sun_pos_z_edit: LineEdit = %SunPosZEdit
@onready var sun_rot_x_edit: LineEdit = %SunRotXEdit
@onready var sun_rot_y_edit: LineEdit = %SunRotYEdit
@onready var sun_rot_z_edit: LineEdit = %SunRotZEdit
@onready var sun_intensity_slider: HSlider = %SunIntensitySlider
@onready var sun_intensity_value_label: Label = %SunIntensityValueLabel
@onready var update_btn: Button = %UpdateButton

func _ready():
	# NEW: Make the window modal, which blocks input to the main scene when visible.
	exclusive = true
	
	# Connect signals from UI elements to their handlers.
	update_btn.pressed.connect(_on_update_sun_pressed)
	sun_intensity_slider.value_changed.connect(_on_sun_intensity_slider_changed)
	close_requested.connect(hide)

# Public method to open the dialog and populate it with the current sun state.
func open_with_settings(current_settings: Dictionary):
	# Populate position fields
	var pos = current_settings.get("position", Vector3.ZERO)
	sun_pos_x_edit.text = str(pos.x)
	sun_pos_y_edit.text = str(pos.y)
	sun_pos_z_edit.text = str(pos.z)
	
	# Populate rotation fields
	var rot = current_settings.get("rotation_degrees", Vector3(-50, -30, 0))
	sun_rot_x_edit.text = str(rot.x)
	sun_rot_y_edit.text = str(rot.y)
	sun_rot_z_edit.text = str(rot.z)

	# Populate intensity slider
	var energy = current_settings.get("energy", 0.1)
	sun_intensity_slider.value = energy
	sun_intensity_value_label.text = str(snapped(energy, 0.01))
	
	popup_centered()

# Called when the intensity slider value changes.
func _on_sun_intensity_slider_changed(value: float):
	sun_intensity_value_label.text = str(snapped(value, 0.01))

# Called when the "Update Sun" button is pressed.
func _on_update_sun_pressed():
	# Gather all values from the UI fields.
	var new_settings = {
		"position": Vector3(
			sun_pos_x_edit.text.to_float(),
			sun_pos_y_edit.text.to_float(),
			sun_pos_z_edit.text.to_float()
		),
		"rotation_degrees": Vector3(
			sun_rot_x_edit.text.to_float(),
			sun_rot_y_edit.text.to_float(),
			sun_rot_z_edit.text.to_float()
		),
		"energy": sun_intensity_slider.value
	}
	
	# Emit the signal with the new data and hide the dialog.
	emit_signal("sun_updated", new_settings)
	hide()
