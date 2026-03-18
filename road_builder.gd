# road_builder.gd

extends Node

# --- Signals ---
# Emitted when the scene has been modified by the road builder.
signal scene_modified

# --- Dependencies ---
var placed_models_container: Node3D
var grid_data: Dictionary
var level_editor # Reference to the main level editor script.

# --- Config ---
# Maps the type of road piece to its resource path.
const ROAD_MODELS = {
	"end": "res://models/road-builder/road-end.glb",
	"straight": "res://models/road-builder/road-straight.glb",
	"corner": "res://models/road-builder/road-bend-sidewalk.glb",
	"intersection": "res://models/road-builder/road-intersection.glb",
	"crossroad": "res://models/road-builder/road-crossroad.glb"
}

# Defines which directions each road type connects to in its default rotation (0 degrees).
const ROAD_CONNECTIONS = {
	"end": [Vector2.RIGHT],
	"straight": [Vector2.LEFT, Vector2.RIGHT],
	"corner": [Vector2.RIGHT, Vector2.DOWN],
	"intersection": [Vector2.LEFT, Vector2.RIGHT, Vector2.DOWN],
	"crossroad": [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]
}

# --- Public API ---

# Initializes the road builder with necessary references from the level editor.
func initialize(editor, container, data):
	level_editor = editor
	placed_models_container = container
	grid_data = data

# Main function to place a road at a specific grid position.
# It handles both creating a new road and updating existing ones.
func place_road(grid_pos: Vector2):
	# Prevent placing a road on top of an existing road piece.
	if _is_road_at(grid_pos):
		print("Road already exists at this position.")
		return
		
	# Place the initial piece and then update its neighbors.
	_place_or_update_road_at(grid_pos)
	for neighbor_offset in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		_place_or_update_road_at(grid_pos + neighbor_offset)
	
	emit_signal("scene_modified")

# Called when a model is deleted, to update adjacent roads.
func on_model_deleted(grid_pos: Vector2):
	# Update all neighbors of the deleted piece.
	for neighbor_offset in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var neighbor_pos = grid_pos + (neighbor_offset * Vector2(level_editor.tile_x, level_editor.tile_z))
		if _is_road_at(neighbor_pos):
			_place_or_update_road_at(neighbor_pos)

# --- Internal Logic ---

# Core function that determines the correct road piece and rotation for a given position.
func _place_or_update_road_at(grid_pos: Vector2):
	if not _is_road_at(grid_pos):
		return # Only update existing road pieces.

	var neighbors = _get_road_neighbors(grid_pos)
	var connection_count = neighbors.size()
	var road_type = ""
	var rotation_y = 0.0

	# Determine the road type based on the number of connections.
	match connection_count:
		0:
			road_type = "end" # Should not happen if called from an existing road.
		1:
			road_type = "end"
			if neighbors.has(Vector2.UP): rotation_y = 270.0
			elif neighbors.has(Vector2.DOWN): rotation_y = 90.0
			elif neighbors.has(Vector2.LEFT): rotation_y = 180.0
		2:
			# Straight or Corner
			if (neighbors.has(Vector2.LEFT) and neighbors.has(Vector2.RIGHT)) or \
			   (neighbors.has(Vector2.UP) and neighbors.has(Vector2.DOWN)):
				road_type = "straight"
				if neighbors.has(Vector2.UP): rotation_y = 90.0
			else:
				road_type = "corner"
				if neighbors.has(Vector2.UP) and neighbors.has(Vector2.RIGHT): rotation_y = 270.0
				elif neighbors.has(Vector2.UP) and neighbors.has(Vector2.LEFT): rotation_y = 180.0
				elif neighbors.has(Vector2.DOWN) and neighbors.has(Vector2.LEFT): rotation_y = 90.0
		3:
			road_type = "intersection"
			if not neighbors.has(Vector2.RIGHT): rotation_y = 180.0
			elif not neighbors.has(Vector2.UP): rotation_y = 90.0
			elif not neighbors.has(Vector2.LEFT): rotation_y = 0.0 # Default is open left, right, down
			elif not neighbors.has(Vector2.DOWN): rotation_y = 270.0
		4:
			road_type = "crossroad"
		_:
			# If something went wrong, remove the piece.
			_delete_road_at(grid_pos)
			return

	# If no valid type was found, do nothing.
	if road_type.is_empty():
		return

	var existing_road = _get_road_node_at(grid_pos)
	var new_model_path = ROAD_MODELS[road_type]

	# If the existing road is not the correct type, replace it.
	if not is_instance_valid(existing_road) or existing_road.get_meta("model_path") != new_model_path:
		_delete_road_at(grid_pos)
		_create_road_piece(grid_pos, road_type, rotation_y)
	else:
		# If it's the correct type, just update its rotation.
		existing_road.rotation_degrees.y = rotation_y


# Creates and places a new road piece instance in the scene.
func _create_road_piece(grid_pos: Vector2, type: String, rotation_y: float):
	var model_path = ROAD_MODELS[type]
	var scene = load(model_path)
	if scene:
		var instance = scene.instantiate()
		instance.position = Vector3(grid_pos.x, 0, grid_pos.y)
		instance.scale = Vector3.ONE # Road pieces should have a uniform scale of 1.
		instance.rotation_degrees.y = rotation_y
		instance.set_meta("model_path", model_path)
		instance.set_meta("model_scale", 1.0)
		instance.set_meta("uses_grid_snap", true)
		# NEW: Add a meta tag to identify road builder pieces.
		instance.set_meta("is_road", true) 
		
		level_editor._configure_shadows_for_node(instance)
		placed_models_container.add_child(instance)
		
		if not grid_data.has(grid_pos):
			grid_data[grid_pos] = []
		grid_data[grid_pos].append(instance)

# Deletes a road piece at a given grid position.
func _delete_road_at(grid_pos: Vector2):
	if grid_data.has(grid_pos):
		var models_on_tile: Array = grid_data[grid_pos]
		for i in range(models_on_tile.size() - 1, -1, -1):
			var model = models_on_tile[i]
			if is_instance_valid(model) and model.get_meta("is_road", false):
				models_on_tile.remove_at(i)
				model.queue_free()
		if models_on_tile.is_empty():
			grid_data.erase(grid_pos)

# Checks which of the four cardinal neighbors of a grid cell also contain a road.
func _get_road_neighbors(grid_pos: Vector2) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var tile_size = Vector2(level_editor.tile_x, level_editor.tile_z)
	
	if _is_road_at(grid_pos + Vector2(0, -tile_size.y)): result.append(Vector2.UP)
	if _is_road_at(grid_pos + Vector2(0, tile_size.y)): result.append(Vector2.DOWN)
	if _is_road_at(grid_pos + Vector2(-tile_size.x, 0)): result.append(Vector2.LEFT)
	if _is_road_at(grid_pos + Vector2(tile_size.x, 0)): result.append(Vector2.RIGHT)
		
	return result

# Helper to check if a road piece exists at a specific grid position.
func _is_road_at(grid_pos: Vector2) -> bool:
	return is_instance_valid(_get_road_node_at(grid_pos))

# Helper to get the actual road node at a grid position.
func _get_road_node_at(grid_pos: Vector2) -> Node3D:
	if grid_data.has(grid_pos):
		var models_on_tile: Array = grid_data[grid_pos]
		for model in models_on_tile:
			if is_instance_valid(model) and model.get_meta("is_road", false):
				return model
	return null
