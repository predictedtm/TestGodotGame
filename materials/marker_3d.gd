# Waypoint.gd
extends Marker3D
class_name Waypoint

## The default and maximum interest level of this waypoint.
@export var max_interest: float = 1.0
## How quickly the interest restores per second when the walker is far away.
@export var restoration_rate: float = 0.1

var current_interest: float = 0.0

func _ready() -> void:
	# Start with full interest.
	current_interest = max_interest

# This is called by the RandomWalker to dynamically adjust interest.
func update_interest(walker_position: Vector3, delta: float) -> void:
	var distance: float = global_transform.origin.distance_to(walker_position)
	
	# Check if the walker is "very close" (e.g., within 2 units)
	# This range determines when interest starts to "deprecate"
	var close_distance: float = 2.0 
	
	if distance < close_distance:
		# DEPRECATE (Decrease) interest if the walker is very close
		# Use a higher rate for fast depletion
		var depletion_rate = 1.0 # Deplete quickly when standing on top of it
		current_interest -= depletion_rate * delta
		print("depletion")
	else:
		# RESTORE interest when the walker is far away
		current_interest += restoration_rate * delta
		
	# Clamp the value between 0 and max_interest
	current_interest = clamp(current_interest, 0.0, max_interest)
	print(current_interest)
