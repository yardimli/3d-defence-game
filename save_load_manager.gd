extends Window

# Emitted when the user requests to save the scene with a given name.
signal save_requested(scene_name: String)
# Emitted when the user requests to load the selected scene.
signal load_requested(scene_name: String)

const SAVE_DIR = "user://levels/"

# --- State ---
var _is_updating_text_from_selection := false

# --- Node-Referenzen ---
@onready var scene_name_edit: LineEdit = %SceneNameEdit
@onready var save_button: Button = %SaveButton
@onready var load_button: Button = %LoadButton
@onready var delete_button: Button = %DeleteButton
@onready var scene_list: ItemList = %SceneList
@onready var confirm_delete_dialog: ConfirmationDialog = %ConfirmDeleteDialog

func _ready():
	# Make the window modal, which blocks input to the main scene when visible.
	exclusive = true
	
	# Ensure the save directory exists.
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	
	# Connect UI signals.
	save_button.pressed.connect(_on_save_pressed)
	load_button.pressed.connect(_on_load_pressed)
	delete_button.pressed.connect(_on_delete_pressed)
	confirm_delete_dialog.confirmed.connect(_on_delete_confirmed)
	
	scene_list.item_selected.connect(_on_scene_selected)
	scene_list.item_activated.connect(_on_item_activated)
	scene_name_edit.text_changed.connect(_on_scene_name_text_changed)
	close_requested.connect(hide)
	
	# Initial state.
	load_button.disabled = true
	save_button.disabled = true
	delete_button.disabled = true

# Public method to open the dialog.
func open():
	_refresh_scene_list()
	popup_centered()

# Scans the save directory and populates the list of saved scenes.
func _refresh_scene_list():
	scene_list.clear()
	load_button.disabled = true
	delete_button.disabled = true
	
	var dir = DirAccess.open(SAVE_DIR)
	if not dir:
		printerr("Could not open save directory: ", SAVE_DIR)
		return
		
	dir.list_dir_begin()
	var file_name = dir.get_next()
	# Collect file names into an array to be sorted.
	var scene_names = []
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			# Add the name without the extension to our array.
			scene_names.append(file_name.get_basename())
		file_name = dir.get_next()
	
	scene_names.sort()
	
	for name in scene_names:
		scene_list.add_item(name)

func _on_scene_name_text_changed(new_text: String):
	if _is_updating_text_from_selection:
		return

	save_button.disabled = new_text.is_empty()
	scene_list.deselect_all()
	load_button.disabled = true
	delete_button.disabled = true

func _on_scene_selected(_index: int):
	load_button.disabled = false
	delete_button.disabled = false
	var selected_name = scene_list.get_item_text(scene_list.get_selected_items()[0])
	
	_is_updating_text_from_selection = true
	scene_name_edit.text = selected_name
	_is_updating_text_from_selection = false

# Emits the save signal and closes the dialog.
func _on_save_pressed():
	var scene_name = scene_name_edit.text
	if not scene_name.is_empty():
		emit_signal("save_requested", scene_name)
		hide()

# Emits the load signal when the "Load" button is clicked.
func _on_load_pressed():
	var selected_items = scene_list.get_selected_items()
	if not selected_items.is_empty():
		var scene_name = scene_list.get_item_text(selected_items[0])
		emit_signal("load_requested", scene_name)
		hide()

# Handles the item_activated signal from the ItemList (double-click or Enter).
func _on_item_activated(index: int):
	# The signal provides the index directly, which is more reliable than checking selection.
	var scene_name = scene_list.get_item_text(index)
	if not scene_name.is_empty():
		emit_signal("load_requested", scene_name)
		hide()

func _on_delete_pressed():
	var selected_items = scene_list.get_selected_items()
	if selected_items.is_empty():
		return # Should not happen if button is enabled, but good practice.
		
	var scene_name = scene_list.get_item_text(selected_items[0])
	# Customize the confirmation dialog text and show it.
	confirm_delete_dialog.dialog_text = "Are you sure you want to permanently delete '%s'?" % scene_name
	confirm_delete_dialog.popup_centered()

func _on_delete_confirmed():
	var selected_items = scene_list.get_selected_items()
	if selected_items.is_empty():
		return
		
	var scene_name = scene_list.get_item_text(selected_items[0])
	var file_path = SAVE_DIR.path_join(scene_name + ".json")
	
	# Use DirAccess to remove the file.
	var err = DirAccess.remove_absolute(file_path)
	if err == OK:
		print("Deleted file: ", file_path)
		# After deleting, clear the input field and refresh the list.
		scene_name_edit.clear()
		_refresh_scene_list()
	else:
		printerr("Failed to delete file: ", file_path, " with error code: ", err)
