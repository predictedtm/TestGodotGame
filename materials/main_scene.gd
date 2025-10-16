# Example MainScene.gd

extends Node3D

@onready var random_walker: RandomWalker = $RandomWalker
@onready var waypoints_container: Node3D = $Waypoints

func _ready():
	var poi_list: Array[Vector3] = []
	
	# Iterate through all children of the Waypoints container
	for child in waypoints_container.get_children():
		# Check if it's a Marker3D (or any node you use as a waypoint)
		if child is Marker3D:
			# Add its global position to the list
			poi_list.append(child.global_transform.origin)
	
	# Pass the list to the RandomWalker
	random_walker.points_of_interest = poi_list
	
	print("RandomWalker configured with %d points of interest." % poi_list.size())
