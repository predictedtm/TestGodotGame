# WaypointDistributor.gd
extends Node3D

## Defines the half-size of the rectangular area. 
## Markers will be placed randomly between (-PlaneSize.x, -PlaneSize.z) and (PlaneSize.x, PlaneSize.z).
@export var plane_half_size: Vector2 = Vector2(20.0, 20.0)

## The height (Y-coordinate) where all markers should be placed.
@export var placement_height: float = 0.0

## If true, the character will not stop and idle after finishing a walk period.
@export var randomize_on_ready: bool = true

# NOTE: The @tool annotation and the @export var distribute_waypoints 
# have been removed to prevent the script from running in the editor.

func _ready():
	# Only run the randomization logic if the option is enabled.
	# Because @tool is removed, this function ONLY runs in a running game.
	if randomize_on_ready:
		# It's good practice to ensure the random seed is initialized once, 
		# though Godot often handles this automatically.
		randomize()
		_distribute_waypoints()
	
	# If not randomized, the Marker3D nodes will remain at their positions set in the editor.

## Function to distribute the markers randomly within the plane
func _distribute_waypoints() -> void:
	var min_x: float = -plane_half_size.x
	var max_x: float = plane_half_size.x
	var min_z: float = -plane_half_size.y # Using Y component of Vector2 for Z plane
	var max_z: float = plane_half_size.y

	# Iterate through all direct children of this Node3D
	for child in get_children():
		# We only want to move Marker3D nodes
		if child is Marker3D:
			var marker = child as Marker3D
			
			# Generate random X and Z coordinates within the defined bounds
			var random_x: float = randf_range(min_x, max_x)
			var random_z: float = randf_range(min_z, max_z)
			
			# Create the new position vector
			var new_position: Vector3 = Vector3(random_x, placement_height, random_z)
			
			# Set the marker's local position relative to the Waypoints parent node
			marker.position = new_position
