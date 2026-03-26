extends PanelContainer

# Emitted when the user changes the position values.
signal position_changed(new_pos: Vector3)
# Emitted when the user changes the uniform scale.
signal scale_changed(new_scale: float)
# Emitted when the user clicks the up/down buttons for stack order.
signal order_changed(direction: int)
# Emitted when the user toggles the grid snap checkbox.
signal grid_snap_toggled(should_snap: bool)

# --- State ---
var _is_updating := false # Prevents signals from firing when populating fields.
var _selected_node: Node3D = null

# --- Node-Referenzen ---
@onready var grid_pos_label: Label = %GridPosLabel
@onready var pos_x_spinbox: SpinBox = %PosXSpinBox
@onready var pos_y_spinbox: SpinBox = %PosYSpinBox
@onready var pos_z_spinbox: SpinBox = %PosZSpinBox
@onready var scale_spinbox: SpinBox = %ScaleSpinBox
@onready var order_up_button: Button = %OrderUpButton
@onready var order_down_button: Button = %OrderDownButton
@onready var grid_snap_checkbox: CheckBox = %GridSnapCheckbox

func _ready():
	# Connect signals to specific handlers.
	pos_x_spinbox.value_changed.connect(_on_position_value_changed)
	pos_y_spinbox.value_changed.connect(_on_position_value_changed)
	pos_z_spinbox.value_changed.connect(_on_position_value_changed)
	scale_spinbox.value_changed.connect(_on_scale_value_changed)
	
	order_up_button.pressed.connect(_on_order_up_pressed)
	order_down_button.pressed.connect(_on_order_down_pressed)
	# Connect the checkbox's toggled signal.
	grid_snap_checkbox.toggled.connect(_on_grid_snap_toggled)
	
	# Hide the panel on startup.
	hide()

# Public method to toggle the visibility of the panel.
func toggle_visibility():
	visible = not visible

# Public method to populate the panel's fields with data from the selected object.
func update_fields(node: Node3D, models_on_tile: Array, grid_pos: Vector2):
	_is_updating = true
	_selected_node = node
	
	# Update position fields
	grid_pos_label.text = str(grid_pos)
	pos_x_spinbox.value = node.position.x
	pos_y_spinbox.value = node.position.y
	pos_z_spinbox.value = node.position.z
	
	# Update scale field (assumes uniform scaling)
	scale_spinbox.value = node.scale.x
	
	# Update the grid snap checkbox state.
	grid_snap_checkbox.button_pressed = node.get_meta("uses_grid_snap", true)
	
	# Update and manage stack order buttons
	var current_index = models_on_tile.find(node)
	order_up_button.disabled = (current_index == models_on_tile.size() - 1)
	order_down_button.disabled = (current_index == 0)
	
	_is_updating = false
	show()

# Public method to clear fields and hide the panel.
func clear_and_hide():
	_is_updating = true
	_selected_node = null
	pos_x_spinbox.value = 0
	pos_y_spinbox.value = 0
	pos_z_spinbox.value = 0
	scale_spinbox.value = 1
	grid_pos_label.text = ""
	_is_updating = false
	hide()

# Specific handler for any of the position SpinBox values changing.
func _on_position_value_changed(_value: float):
	if _is_updating or not is_instance_valid(_selected_node):
		return
	var new_pos = Vector3(pos_x_spinbox.value, pos_y_spinbox.value, pos_z_spinbox.value)
	emit_signal("position_changed", new_pos)

# Specific handler for the scale SpinBox value changing.
func _on_scale_value_changed(value: float):
	if _is_updating or not is_instance_valid(_selected_node):
		return
	emit_signal("scale_changed", value)

# Handler for the grid snap checkbox being toggled.
func _on_grid_snap_toggled(is_checked: bool):
	if _is_updating or not is_instance_valid(_selected_node):
		return
	emit_signal("grid_snap_toggled", is_checked)

# Handler for the "Up" button.
func _on_order_up_pressed():
	if is_instance_valid(_selected_node):
		emit_signal("order_changed", 1)

# Handler for the "Down" button.
func _on_order_down_pressed():
	if is_instance_valid(_selected_node):
		emit_signal("order_changed", -1)
