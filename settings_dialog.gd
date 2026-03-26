extends Window

# Emitted when a setting is changed by the user.
signal setting_changed(setting_name: String, new_value: Variant)
signal preview_settings_changed(settings: Dictionary)

# --- Node-Referenzen ---
@onready var stacking_checkbox: CheckBox = %StackingCheckbox
@onready var close_button: Button = %CloseButton
@onready var apply_button: Button = %ApplyButton
@onready var model_scale_spinbox: SpinBox = %ModelScaleSpinBox
@onready var cam_pos_x_spinbox: SpinBox = %CamPosXSpinBox
@onready var cam_pos_y_spinbox: SpinBox = %CamPosYSpinBox
@onready var cam_pos_z_spinbox: SpinBox = %CamPosZSpinBox
@onready var look_at_x_spinbox: SpinBox = %LookAtXSpinBox
@onready var look_at_y_spinbox: SpinBox = %LookAtYSpinBox
@onready var look_at_z_spinbox: SpinBox = %LookAtZSpinBox

@onready var cloud_density_slider: HSlider = %CloudDensitySlider
@onready var cloud_speed_slider: HSlider = %CloudSpeedSlider
@onready var terrain_width_spinbox: SpinBox = %TerrainWidthSpinBox
@onready var terrain_depth_spinbox: SpinBox = %TerrainDepthSpinBox
@onready var tree_density_spinbox: SpinBox = %TreeDensitySpinBox

func _ready():
	exclusive = true
	
	stacking_checkbox.toggled.connect(_on_stacking_checkbox_toggled)
	close_button.pressed.connect(hide)
	apply_button.pressed.connect(_on_apply_pressed)
	close_requested.connect(hide)
	
	cloud_density_slider.value_changed.connect(_on_cloud_density_changed)
	cloud_speed_slider.value_changed.connect(_on_cloud_speed_changed)
	terrain_width_spinbox.value_changed.connect(_on_terrain_width_changed)
	terrain_depth_spinbox.value_changed.connect(_on_terrain_depth_changed)
	tree_density_spinbox.value_changed.connect(_on_tree_density_changed)

func open_with_settings(current_settings: Dictionary):
	var allow_stacking = current_settings.get("allow_same_asset_stacking", false)
	stacking_checkbox.button_pressed = allow_stacking
	
	model_scale_spinbox.value = current_settings.get("model_scale", 1.0)
	
	var cam_pos: Vector3 = current_settings.get("position", Vector3(0, 1.0, 2.5))
	cam_pos_x_spinbox.value = cam_pos.x
	cam_pos_y_spinbox.value = cam_pos.y
	cam_pos_z_spinbox.value = cam_pos.z
	
	var look_at: Vector3 = current_settings.get("look_at", Vector3.ZERO)
	look_at_x_spinbox.value = look_at.x
	look_at_y_spinbox.value = look_at.y
	look_at_z_spinbox.value = look_at.z
	
	cloud_density_slider.value = current_settings.get("cloud_density", 0.5)
	cloud_speed_slider.value = current_settings.get("cloud_speed", 0.02)
	terrain_width_spinbox.value = current_settings.get("terrain_width", 100)
	terrain_depth_spinbox.value = current_settings.get("terrain_depth", 100)
	tree_density_spinbox.value = current_settings.get("tree_density", 2.0)
	
	popup_centered()

func _on_stacking_checkbox_toggled(is_checked: bool):
	emit_signal("setting_changed", "allow_same_asset_stacking", is_checked)

func _on_apply_pressed():
	var override_settings = {
		"model_scale": model_scale_spinbox.value,
		"position": Vector3(cam_pos_x_spinbox.value, cam_pos_y_spinbox.value, cam_pos_z_spinbox.value),
		"look_at": Vector3(look_at_x_spinbox.value, look_at_y_spinbox.value, look_at_z_spinbox.value)
	}
	emit_signal("preview_settings_changed", override_settings)

func _on_cloud_density_changed(value: float):
	emit_signal("setting_changed", "cloud_density", value)

func _on_cloud_speed_changed(value: float):
	emit_signal("setting_changed", "cloud_speed", value)

func _on_terrain_width_changed(value: float):
	emit_signal("setting_changed", "terrain_width", int(value))

func _on_terrain_depth_changed(value: float):
	emit_signal("setting_changed", "terrain_depth", int(value))

func _on_tree_density_changed(value: float):
	emit_signal("setting_changed", "tree_density", value)
