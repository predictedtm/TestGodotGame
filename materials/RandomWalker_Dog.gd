class_name RandomWalker
extends CharacterBody3D

@export_group("Movement Settings")
## The average speed for random walks or general travel.
@export var base_speed: float = 3.5 
## Minimum speed when near a high-interest POI (focus).
@export var min_focus_speed: float = 1.0 
## The distance (radius) within which speed starts to decrease.
@export var focus_distance: float = 5.0 
## How fast the character visually turns. Higher is faster.
@export var rotation_speed: float = 5.0
## How sharply the character changes its movement path. Lower values create wider, more circular turns.
@export var turn_agility: float = 3.0
## Gravity applied to the character.
@export var gravity: float = 9.8

@export_group("Behavior Flags")
## If true, the walker will stop immediately when it reaches a Point of Interest (POI) marker.
@export var stop_at_marker: bool = false
## Distance threshold to consider the target 'reached'
const STOPPING_DISTANCE: float = 0.5 

## The range of time [min, max] the character will walk in one direction.
@export_group("Walk Settings")
@export var min_walk_time: float = 2.0
@export var max_walk_time: float = 5.0
@export var no_random_break: bool = false

## The range of time [min, max] the character will stay idle.
@export_group("Idle Settings")
@export var min_idle_time: float = 1.0
@export var max_idle_time: float = 4.0

@export_group("Goal Seeking")
## The name of the metadata key (e.g., "is_poi") required for a Marker3D to be tracked.
@export var poi_tag_key: String = "is_poi"
@export var poi_walk_chance: float = 0.5
@export var time_for_target_reconsideration: float = 0.5
@export var target_persistence_chance: float = 0.9 
@export var temptation_threshold: float = 1.0 
@export var temptation_distance_influence: float = 2.0 

@export_group("POI Interest Settings")
@export var max_interest: float = 1.0
@export var restoration_rate: float = 0.1
@export var depletion_rate: float = 1.0 
@export var depletion_distance: float = 2.0
@export var max_depletion_multiplier: float = 5.0 


# Stores waypoint data: [{ "node": Node, "name": String, "category": int (enum) }, ...]
var waypoint_data: Array[Dictionary] = [] 
# Dictionary to track interest: {Node (reference) : float (interest_level)}
var poi_interests: Dictionary = {}

enum State { IDLE, WALK }

# Marker Categories for behavioral classification
enum MarkerCategory {
	FOOD,
	HUMAN,
	ANIMAL,
	PREY,
	GRASS,
	LAWN,
	GENERAL # Default category
}

var current_state: State = State.IDLE
var target_direction: Vector3 = Vector3.FORWARD
var current_movement_direction: Vector3 = Vector3.FORWARD
# NEW: Track the current POI node reference for dynamic position updates
var current_target_poi_node: Node = null 
# Track the current POI position goal (used primarily for the stop_at_marker check)
var current_target_poi_pos: Vector3 = Vector3.ZERO 

@onready var state_timer: Timer = $StateTimer
@onready var dir_timer: Timer = $DirectionTimer


func _ready() -> void:
	# Start searching from the root of the entire scene tree
	if Engine.is_editor_hint():
		# In editor, use the current scene root for POI collection
		_populate_points_of_interest(get_tree().get_edited_scene_root())
	else:
		# In game, use the current scene root
		_populate_points_of_interest(get_tree().get_root())
	
	state_timer.timeout.connect(_on_state_timer_timeout)
	dir_timer.timeout.connect(_on_dir_timer_timeout)
	dir_timer.wait_time = time_for_target_reconsideration
	dir_timer.autostart = true
	dir_timer.one_shot = false
	
	_pick_random_direction()
	current_movement_direction = target_direction
	_on_state_timer_timeout()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	_update_waypoint_interests(delta)
	
	var dynamic_speed = _calculate_dynamic_speed()
	
	match current_state:
		State.IDLE:
			_handle_idle_state()
		State.WALK:
			_handle_walk_state(delta, dynamic_speed) 
			
	move_and_slide()


## Calculates speed based on proximity to the most interesting POI. (Simplified Fluctuation)
func _calculate_dynamic_speed() -> float:
	if current_state == State.IDLE:
		return 0.0

	var walker_position: Vector3 = global_transform.origin
	var max_influence_factor: float = 0.0
	var speed_base: float = base_speed
	
	# Calculate proximity-based slow down (focus)
	for data in waypoint_data:
		var poi_node: Node = data.node       # <-- Get the Node
		var poi_pos: Vector3 = poi_node.global_transform.origin # <-- Get current position
		var current_interest: float = poi_interests.get(poi_node, 0.0) # <-- Use Node as key
		
		if current_interest > 0.0:
			var distance: float = walker_position.distance_to(poi_pos)
			
			if distance < focus_distance:
				var proximity: float = 1.0 - (distance / focus_distance)
				var normalized_interest: float = current_interest / max_interest
				var influence_factor: float = proximity * normalized_interest
				
				max_influence_factor = max(max_influence_factor, influence_factor)

	# Calculate final speed: Lerp from the base speed down to min_focus_speed
	var calculated_speed = lerp(speed_base, min_focus_speed, max_influence_factor)

	# LOG: Speed change
	var current_base = speed_base 
	if abs(calculated_speed - current_base) > 0.1:
		print("🚶 Speed adjusted: Base(", snb(current_base), ") -> Final(", snb(calculated_speed), ") (Influence: ", snb(max_influence_factor), ")")
	
	return calculated_speed

## -----------------------------------------------------------------------------
## PRIVATE RECURSIVE FUNCTION
## -----------------------------------------------------------------------------

## Recursively searches the node tree for Marker3D nodes with the required POI tag.
func _find_tagged_markers_recursive(node: Node, markers: Array) -> void:
	if node is Marker3D and node.has_meta(poi_tag_key):
		# Check if the metadata value is non-empty or true (if using bool meta)
		var tag_value = node.get_meta(poi_tag_key)
		if tag_value != null and tag_value != false: 
			markers.append(node)
	
	for child in node.get_children():
		# Recursive call is now clean and within the class scope
		_find_tagged_markers_recursive(child, markers)

## -----------------------------------------------------------------------------
## POPULATE POIS FUNCTION (UPDATED FOR NODE REFERENCE)
## -----------------------------------------------------------------------------

## Helper function to collect Marker3D positions and initialize interest using a scene-wide tag search.
func _populate_points_of_interest(root_node: Node) -> void:
	waypoint_data.clear()
	poi_interests.clear()
	
	var poi_count = 0
	var category_keys = MarkerCategory.keys()
	
	var tagged_markers: Array = []
	# Initial call to the new private recursive method
	_find_tagged_markers_recursive(root_node, tagged_markers)
	
	for child in tagged_markers:
		var pos: Vector3 = child.global_transform.origin # Only used for logging here, not saved
		var poi_name: String = child.get_meta("poi_name", child.name)
		
		# Robustly retrieve category metadata
		var raw_meta = child.get_meta("poi_type")
		var type_string: String
		
		if raw_meta is String:
			type_string = raw_meta.to_upper()
		else:
			type_string = "GENERAL"
		
		# Initialize poi_category to a safe integer default
		var poi_category: int = MarkerCategory.GENERAL
		
		# Check if the string exists in the enum keys
		var category_index = category_keys.find(type_string)
		
		if category_index != -1:
			# If found, the array index is the correct enum integer value.
			poi_category = category_index
		else:
			print("⚠️ POI '", poi_name, "' has invalid category '", type_string, "'. Using GENERAL.")
		
		# Store data - IMPORTANT: storing the NODE REFERENCE
		waypoint_data.append({
			"node": child,                      # <-- Storing the Node reference
			"name": poi_name,
			"category": poi_category, 
			"material": null
		}) 
		# IMPORTANT: using the NODE REFERENCE as the key for interest
		poi_interests[child] = max_interest 
		poi_count += 1

	if poi_count == 0:
		print("⚠️ Warning: RandomWalker found no Marker3D tagged with '", poi_tag_key, "'. Reverting to purely random walk.")
	else:
		print("✅ RandomWalker initialized with ", poi_count, " points of interest using tag '", poi_tag_key, "'.")


## Helper function to continuously update the interest level 
func _update_waypoint_interests(delta: float) -> void:
	var walker_position: Vector3 = global_transform.origin
	
	for data in waypoint_data:
		var poi_node: Node = data.node       # <-- Get the Node
		# Get the current position for distance check
		var poi_pos: Vector3 = poi_node.global_transform.origin 
		
		var current_interest: float = poi_interests.get(poi_node, 0.0) # <-- Use Node as key
		var old_interest: float = current_interest
		
		if current_interest == 0.0 and not poi_interests.has(poi_node):
			poi_interests[poi_node] = max_interest # <-- Use Node as key
			current_interest = max_interest
			old_interest = max_interest
		
		var distance: float = walker_position.distance_to(poi_pos)
		var interest_change_type = ""
		
		if distance < depletion_distance:
			# Depletion (Closer = Faster Depletion)
			var proximity_factor: float = 1.0 - (distance / depletion_distance)
			var rate_multiplier: float = lerp(1.0, max_depletion_multiplier, proximity_factor)
			var dynamic_rate: float = depletion_rate * rate_multiplier
			current_interest -= dynamic_rate * delta
			interest_change_type = "Depleted"
		else:
			# Restoration (Farther = Fixed Restoration Rate)
			current_interest += restoration_rate * delta
			interest_change_type = "Restored"
			
		current_interest = clamp(current_interest, 0.0, max_interest)
		poi_interests[poi_node] = current_interest # <-- Use Node as key to save
		
		# LOG: Interest Change
		if abs(old_interest - current_interest) > 0.001:
			var change_amount = abs(old_interest - current_interest)
			if (interest_change_type == "Depleted" and change_amount > 0.01) or (interest_change_type == "Restored" and change_amount > 0.05):
				# Get category name for logging
				var category_name = MarkerCategory.keys()[data.category]
				print("🎯 POI Interest ", interest_change_type, " [", category_name, ": ", data.name, "] (Dist:", snb(distance), "): ", snb(old_interest), " -> ", snb(current_interest))


func _on_state_timer_timeout() -> void:
	if current_state == State.WALK:
		current_state = State.IDLE
		state_timer.wait_time = randf_range(min_idle_time, max_idle_time)
		print("🛑 State Change: WALK -> IDLE for ", snb(state_timer.wait_time), "s.")
		dir_timer.stop() 
	else:
		current_state = State.WALK
		state_timer.wait_time = randf_range(min_walk_time, max_walk_time)
		print("🏃 State Change: IDLE -> WALK for ", snb(state_timer.wait_time), "s.")
		_pick_random_direction()
		dir_timer.start()
	
	if not no_random_break:
		state_timer.start()


func _handle_walk_state(delta: float, current_speed: float) -> void:
	
	# DYNAMIC MARKER UPDATE: If a POI node is the target, continuously re-evaluate its direction
	if current_target_poi_node != null:
		var target_position: Vector3 = current_target_poi_node.global_transform.origin
		var direction_to_target: Vector3 = target_position - global_transform.origin
		direction_to_target.y = 0 # Keep it flat
		target_direction = direction_to_target.normalized()
		# Update the stop_at_marker position for dynamic tracking
		current_target_poi_pos = target_position 
	
	current_movement_direction = current_movement_direction.slerp(target_direction, turn_agility * delta)
	velocity.x = current_movement_direction.x * current_speed
	velocity.z = current_movement_direction.z * current_speed
	
	# --- STOP-AT-MARKER LOGIC ---
	if stop_at_marker and current_target_poi_pos != Vector3.ZERO:
		# Use current_target_poi_pos which is updated every frame if a POI is targeted
		var distance = global_transform.origin.distance_to(current_target_poi_pos)
		
		if distance < STOPPING_DISTANCE:
			current_state = State.IDLE
			state_timer.wait_time = randf_range(min_idle_time, max_idle_time)
			state_timer.start() 
			dir_timer.stop() 
			# Manually zero out velocity to stop immediately
			velocity.x = 0.0
			velocity.z = 0.0
			current_target_poi_pos = Vector3.ZERO # Clear the target position
			current_target_poi_node = null      # Clear the target node reference
			print("🛑 Reached POI. Transitioning to IDLE.")
			return # Exit the function immediately
	# --- END LOGIC ---
	
	if current_movement_direction != Vector3.ZERO:
		var flat_direction = current_movement_direction
		flat_direction.y = 0
		if flat_direction.length_squared() > 0.0:
			var target_basis = Basis.looking_at(flat_direction)
			transform.basis = transform.basis.slerp(target_basis, rotation_speed * delta)


func _handle_idle_state() -> void:
	velocity.x = lerp(velocity.x, 0.0, 0.1)
	velocity.z = lerp(velocity.z, 0.0, 0.1)


func _on_dir_timer_timeout() -> void:
	if current_state == State.WALK:
		var walker_position: Vector3 = global_transform.origin
		var total_temptation_score: float = 0.0
		
		# Calculate Temptation Score from ALL other POIs
		for data in waypoint_data:
			var poi_node: Node = data.node       # <-- Get the Node
			var poi_pos: Vector3 = poi_node.global_transform.origin # <-- Get current position
			var interest: float = poi_interests.get(poi_node, 0.0) # <-- Use Node as key
			
			var distance: float = max(0.1, walker_position.distance_to(poi_pos))
			
			var distance_factor: float = pow(distance, temptation_distance_influence)
			var temptation_score: float = interest / distance_factor
			
			total_temptation_score += temptation_score
			
		
		# Check if the walker succumbs to temptation
		if total_temptation_score > temptation_threshold:
			print("🚨 Target Change: TEMPTED (Score: ", snb(total_temptation_score), "). Picking new goal.")
			_pick_random_direction() 
			return
		
		# Fall back to the old persistence chance check
		if randf() < target_persistence_chance:
			# If current_target_poi_node is not null, it's a POI goal.
			if current_target_poi_node != null:
				pass 
			return 
		
		# Persistence failed, no high temptation, so choose a new goal randomly.
		print("🔄 Target Change: Persistence failed. Picking new goal.")
		_pick_random_direction()


func _pick_random_direction() -> void:
	# Clear the node reference when picking a random direction
	current_target_poi_node = null
	
	if not waypoint_data.is_empty() and randf() < poi_walk_chance:
		_pick_point_of_interest()
	else:
		var random_angle = randf_range(0, TAU)
		# Ensure direction is flat and normalized
		target_direction = Vector3(sin(random_angle), 0, cos(random_angle)).normalized()
		current_target_poi_pos = Vector3.ZERO
		print("🧭 New Target: Random Walk.")


func _pick_point_of_interest() -> void:
	var current_pos: Vector3 = global_transform.origin
	var total_weight: float = 0.0
	var weights: Array[float] = []
	
	var min_distance_sq: float = 0.01 
	var data_list: Array[Dictionary] = [] 

	for data in waypoint_data:
		var poi_node: Node = data.node                      # <-- Get the Node
		var poi_pos: Vector3 = poi_node.global_transform.origin # <-- Get current position for distance
		data_list.append(data) 
		
		var distance_sq: float = current_pos.distance_squared_to(poi_pos)
		var interest: float = poi_interests.get(poi_node, 0.0) # <-- Use Node as key
		
		if interest <= 0.0:
			weights.append(0.0)
			continue
			
		distance_sq = max(distance_sq, min_distance_sq)
		
		var distance_weight: float = 1.0 / distance_sq
		var final_weight: float = distance_weight * interest
		
		weights.append(final_weight)
		total_weight += final_weight

	if total_weight == 0.0:
		_pick_random_direction()
		return

	var random_value: float = randf() * total_weight
	var chosen_index: int = -1
	var weight_sum: float = 0.0

	for i in range(weights.size()):
		weight_sum += weights[i]
		if random_value < weight_sum:
			chosen_index = i
			break

	if chosen_index != -1:
		var chosen_data: Dictionary = data_list[chosen_index] # Get the full data dictionary
		var chosen_node: Node = chosen_data.node         # <-- Get the chosen Node
		
		# Store the chosen NODE reference for dynamic movement tracking
		current_target_poi_node = chosen_node 
		
		var direction_to_poi: Vector3 = chosen_node.global_transform.origin - current_pos
		
		# Ensure the direction is flat before normalizing
		direction_to_poi.y = 0
		target_direction = direction_to_poi.normalized()
		current_target_poi_pos = chosen_node.global_transform.origin # Update pos for stop check
		
		# LOGGING: Show the Category name and POI name
		var category_name = MarkerCategory.keys()[chosen_data.category]
		print("✨ New Target: POI [", category_name, "] named '", chosen_data.name, "' (Weight: ", snb(weights[chosen_index]), ", Total: ", snb(total_weight), ").")
	else:
		_pick_random_direction()


## Helper function to simplify number formatting for console output
func snb(number: float) -> String:
	return "%0.2f" % number
