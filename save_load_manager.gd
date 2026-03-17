# save_load_manager.gd
extends Window

# Emitted when the user requests to save the scene with a given name.
signal save_requested(scene_name: String)
# Emitted when the user requests to load the selected scene.
signal load_requested(scene_name: String)

const SAVE_DIR = "user://levels/"

# --- Node-Referenzen ---
@onready var scene_name_edit: LineEdit = %SceneNameEdit
@onready var save_button: Button = %SaveButton
@onready var load_button: Button = %LoadButton
@onready var scene_list: ItemList = %SceneList

func _ready():
	# Ensure the save directory exists.
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	
	# Connect UI signals.
	save_button.pressed.connect(_on_save_pressed)
	load_button.pressed.connect(_on_load_pressed)
	scene_list.item_selected.connect(_on_scene_selected)
	scene_name_edit.text_changed.connect(_on_scene_name_text_changed)
	close_requested.connect(hide)
	
	# Initial state.
	load_button.disabled = true
	save_button.disabled = true

# Public method to open the dialog.
func open():
	_refresh_scene_list()
	popup_centered()

# Scans the save directory and populates the list of saved scenes.
func _refresh_scene_list():
	scene_list.clear()
	load_button.disabled = true
	
	var dir = DirAccess.open(SAVE_DIR)
	if not dir:
		printerr("Could not open save directory: ", SAVE_DIR)
		return
		
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			scene_list.add_item(file_name.get_basename())
		file_name = dir.get_next()

# Called when the text in the name input changes.
func _on_scene_name_text_changed(new_text: String):
	save_button.disabled = new_text.is_empty()

# Called when an item in the scene list is selected.
func _on_scene_selected(_index: int):
	load_button.disabled = false
	var selected_name = scene_list.get_item_text(scene_list.get_selected_items()[0])
	scene_name_edit.text = selected_name

# Emits the save signal and closes the dialog.
func _on_save_pressed():
	var scene_name = scene_name_edit.text
	if not scene_name.is_empty():
		emit_signal("save_requested", scene_name)
		hide()

# Emits the load signal and closes the dialog.
func _on_load_pressed():
	var selected_items = scene_list.get_selected_items()
	if not selected_items.is_empty():
		var scene_name = scene_list.get_item_text(selected_items[0])
		emit_signal("load_requested", scene_name)
		hide()
