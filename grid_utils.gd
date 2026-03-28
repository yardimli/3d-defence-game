class_name GridUtils
extends RefCounted

# Extracted grid position calculation uses asset_size parameter to correctly calculate grid position for multi-tile assets.
static func get_grid_pos(position: Vector3, tile_x: float, tile_z: float, asset_size: Vector2i = Vector2i(1, 1)) -> Vector2:
	var offset_x = (tile_x / 2.0) if asset_size.x % 2 == 0 else 0.0
	var offset_z = (tile_z / 2.0) if asset_size.y % 2 == 0 else 0.0
	
	var adjusted_x = position.x - offset_x
	var adjusted_z = position.z - offset_z
	
	var x = round(adjusted_x / tile_x) * tile_x
	var z = round(adjusted_z / tile_z) * tile_z
	
	return Vector2(x + offset_x, z + offset_z)

# Extracted shadow configuration
static func configure_shadows(node: Node):
	if node is MeshInstance3D:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for child in node.get_children():
		configure_shadows(child)

# Extracted mesh gathering
static func get_all_meshes(node: Node, meshes: Array):
	if node is MeshInstance3D:
		meshes.append(node)
	for child in node.get_children():
		get_all_meshes(child, meshes)

# Extracted top Y calculation for stacking
static func get_node_top_y(node: Node3D) -> float:
	var meshes =[]
	get_all_meshes(node, meshes)
	if meshes.is_empty(): 
		return node.global_position.y
		
	var max_y = -INF
	for mi in meshes:
		var aabb = mi.get_aabb()
		var global_xform = mi.global_transform
		var transformed_aabb = global_xform * aabb
		max_y = max(max_y, transformed_aabb.end.y)
	return max_y

# Extracted stack recalculation logic
static func recalculate_stack_y_positions(grid_pos: Vector2, grid_data: Dictionary):
	var models_on_tile: Array = grid_data.get(grid_pos,[])
	if models_on_tile.is_empty(): 
		return
	
	var y_offset = 0.0
	for i in range(models_on_tile.size()):
		var model: Node3D = models_on_tile[i]
		if is_instance_valid(model):
			model.position.y = y_offset
			y_offset = get_node_top_y(model)
