# generate_dog_mesh.gd
@tool
extends EditorScript

func _run():
	var mesh_resource = ArrayMesh.new()
	
	var arrays = []
	arrays.resize(ArrayMesh.ARRAY_MAX)
	
	var vertices: PackedVector3Array = []
	var indices: PackedInt32Array = []
	var uvs: PackedVector2Array = [] # Basic UVs for simple texture mapping

	# 🟢 FIX: Define the helper function as a local variable (a Callable)
	var add_cube = func(size: Vector3, position: Vector3, current_vertex_offset: int):
		var half_size = size / 2.0

		# Vertices for a unit cube centered at origin, then scaled and translated
		var cube_vertices = [
			# Front face
			Vector3(-1, -1,  1), Vector3( 1, -1,  1), Vector3( 1,  1,  1), Vector3(-1,  1,  1),
			# Back face
			Vector3(-1, -1, -1), Vector3(-1,  1, -1), Vector3( 1,  1, -1), Vector3( 1, -1, -1),
			# Top face
			Vector3(-1,  1, -1), Vector3(-1,  1,  1), Vector3( 1,  1,  1), Vector3( 1,  1, -1),
			# Bottom face
			Vector3(-1, -1, -1), Vector3( 1, -1, -1), Vector3( 1, -1,  1), Vector3(-1, -1,  1),
			# Right face
			Vector3( 1, -1, -1), Vector3( 1,  1, -1), Vector3( 1,  1,  1), Vector3( 1, -1,  1),
			# Left face
			Vector3(-1, -1, -1), Vector3(-1, -1,  1), Vector3(-1,  1,  1), Vector3(-1,  1, -1)
		]
		
		# Cube indices (standard triangles for a cube)
		var cube_indices = [
			0, 1, 2,  2, 3, 0,    # Front
			4, 5, 6,  6, 7, 4,    # Back
			8, 9, 10, 10, 11, 8,  # Top
			12, 13, 14, 14, 15, 12, # Bottom
			16, 17, 18, 18, 19, 16, # Right
			20, 21, 22, 22, 23, 20  # Left
		]
		
		# Simple UVs for each face
		var cube_uvs = [
			Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), # Front
			Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), Vector2(0, 1), # Back
			Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), # Top
			Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), # Bottom
			Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), # Right
			Vector2(1, 1), Vector2(0, 1), Vector2(0, 0), Vector2(1, 0)  # Left
		]

		# Apply scaling and translation
		for i in range(cube_vertices.size()):
			# Note: The helper function needs access to the main arrays (vertices, uvs, indices)
			# which are defined outside the func but inside _run. This works in GDScript 2.0.
			vertices.append(cube_vertices[i] * half_size + position)
			uvs.append(cube_uvs[i]) 
		
		# Adjust indices by the current vertex offset
		for idx in cube_indices:
			indices.append(idx + current_vertex_offset)

	# Define dog body parts (sizes and relative positions)
	var body_size = Vector3(0.6, 0.3, 0.25)
	var head_size = Vector3(0.25, 0.25, 0.25)
	var leg_size = Vector3(0.08, 0.3, 0.08)
	var tail_size = Vector3(0.08, 0.08, 0.3)

	# Current vertex count for offsetting indices
	var current_offset = 0

	# Body
	add_cube.call(body_size, Vector3(0, body_size.y/2, 0), current_offset)
	current_offset += 24 # Each cube adds 24 vertices

	# Head
	add_cube.call(head_size, Vector3(body_size.x/2 + head_size.x/2, body_size.y/2 + head_size.y/4, 0), current_offset)
	current_offset += 24

	# Tail (pointing slightly up and back)
	add_cube.call(tail_size, Vector3(-body_size.x/2 - tail_size.x/2, body_size.y/2 + tail_size.y/4, 0), current_offset)
	current_offset += 24

	# Legs (4 legs)
	# Front-left
	add_cube.call(leg_size, Vector3(body_size.x/4, -leg_size.y/2, body_size.z/4), current_offset)
	current_offset += 24
	# Front-right
	add_cube.call(leg_size, Vector3(body_size.x/4, -leg_size.y/2, -body_size.z/4), current_offset)
	current_offset += 24
	# Back-left
	add_cube.call(leg_size, Vector3(-body_size.x/4, -leg_size.y/2, body_size.z/4), current_offset)
	current_offset += 24
	# Back-right
	add_cube.call(leg_size, Vector3(-body_size.x/4, -leg_size.y/2, -body_size.z/4), current_offset)
	current_offset += 24


	arrays[ArrayMesh.ARRAY_VERTEX] = vertices
	arrays[ArrayMesh.ARRAY_INDEX] = indices
	arrays[ArrayMesh.ARRAY_TEX_UV] = uvs 

	# Setup flags for auto-generation of normals and tangents
	var array_flags = Mesh.ARRAY_FORMAT_VERTEX | Mesh.ARRAY_FORMAT_INDEX | Mesh.ARRAY_FORMAT_NORMAL | Mesh.ARRAY_FORMAT_TANGENT | Mesh.ARRAY_FORMAT_TEX_UV
	
	# Final Mesh Construction
	mesh_resource.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, array_flags)
	
	# Save the mesh to a file
	var path = "res://StylizedDogMesh.res"
	ResourceSaver.save(mesh_resource, path)
	print("Stylized dog mesh saved to: " + path)
