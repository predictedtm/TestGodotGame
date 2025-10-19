class_name RandomWalker
extends CharacterBody3D

#==============================================================================
# POI Categories
#==============================================================================

enum MarkerCategory {
	FOOD, HUMAN, ANIMAL, PREY, GRASS, LAWN, GENERAL 
}

#==============================================================================
# EXPORTED SETTINGS
#==============================================================================

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

@export_group("Walk Settings")
## The range of time [min, max] the character will walk in one direction.
@export var min_walk_time: float = 2.0
@export var max_walk_time: float = 5.0
@export var no_random_break: bool = false

@export_group("Idle Settings")
## The range of time [min, max] the character will stay idle.
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

@export_group("Interest Dynamics")
@export var max_interest: float = 10.0
@export var min_interest: float = -5.0        
@export var restoration_rate: float = 0.1     
@export var depletion_rate: float = 2.0       
@export var depletion_distance: float = 3.0   
@export var max_depletion_multiplier: float = 5.0 
@export var stimulus_decay_rate: float = 0.5  

## Dictionary to configure initial interest levels by category name, exported for editor control.
@export var initial_interests_config: Dictionary = {
	"FOOD": 10.0,
	"HUMAN": 5.0,
	"GENERAL": 1.0
} : set = _set_initial_interests, get = _get_initial_interests

@export_group("Leash Settings (Player Anchor)")
@export var leash_target_node: Node3D = null # Set this in the editor to your MainPlayer's anchor point
@export var leash_rest_length: float = 4.0   # Max distance before the pull starts
@export var leash_stiffness: float = 0.5     # How strongly the walker is pulled back

#==============================================================================
# INTERNAL VARIABLES & ENUMS
#==============================================================================

# Stores waypoint data: [{ "node": Node, "category": int (enum), ... }, ...]
var waypoint_data: Array[Dictionary] = [] 

# Tracks interest PER CATEGORY: {MarkerCategory (int) : float (interest_level)}
# This is the dictionary used at runtime, initialized from the exported config.
var category_interests: Dictionary = {} 

enum State { IDLE, WALK }

var current_state: State = State.IDLE
var target_direction: Vector3 = Vector3.FORWARD
var current_movement_direction: Vector3 = Vector3.FORWARD

# Dynamic Marker Tracking
var current_target_poi_node: Node = null 
var current_target_poi_pos: Vector3 = Vector3.ZERO 

@onready var state_timer: Timer = $StateTimer
@onready var dir_timer: Timer = $DirectionTimer
# Assuming you added a Node3D named 'WalkerConnectionPoint' for anchor checks
@onready var walker_anchor: Node3D = $WalkerConnectionPoint 

#==============================================================================
# EXPORT HELPER FUNCTIONS
#==============================================================================

# Getter for the exported property (simple return)
func _get_initial_interests() -> Dictionary:
	return initial_interests_config

# Setter for the exported property (ensures keys are strings for editor)
func _set_initial_interests(new_value: Dictionary) -> void:
	initial_interests_config = new_value

#==============================================================================
# CORE ENGINE FUNCTIONS
#==============================================================================

func _ready() -> void:
	# Populate POIs
	var root_node = get_tree().get_edited_scene_root() if Engine.is_editor_hint() else get_tree().get_root()
	_populate_points_of_interest(root_node)
	
	# Initialize category_interests from exported config
	var category_keys = MarkerCategory.keys()
	for i in MarkerCategory.values():
		var category_name = category_keys[i]
		
		var initial_interest = max_interest # Default value
		
		# Check if the exported dictionary contains a value for this category name
		if initial_interests_config.has(category_name):
			# Convert to float and use exported value
			initial_interest = float(initial_interests_config[category_name])
		
		category_interests[i] = clamp(initial_interest, min_interest, max_interest)
	
	# Output the initial setup for verification
	print("📊 Initial Category Interests:")
	for key in category_interests:
		print("  - ", category_keys[key], ": ", snb(category_interests[key]))
	
	state_timer.timeout.connect(_on_state_timer_timeout)
	dir_timer.timeout.connect(_on_dir_timer_timeout)
	dir_timer.wait_time = time_for_target_reconsideration
	dir_timer.autostart = true
	dir_timer.one_shot = false
	
	_pick_random_direction()
	current_movement_direction = target_direction
	_on_state_timer_timeout() # Initialize state

func _physics_process(delta: float) -> void:
	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	_update_waypoint_interests(delta) # Updates Category Interest
	
	var dynamic_speed = _calculate_dynamic_speed()
	
	match current_state:
		State.IDLE:
			_handle_idle_state()
		State.WALK:
			_handle_walk_state(delta, dynamic_speed) 
			
	move_and_slide()

#==============================================================================
# PUBLIC STIMULUS FUNCTIONS
#==============================================================================

## Applies a positive change to a category's interest level.
## Call this externally, e.g., on body entered area.
func apply_positive_stimulus(category: int, amount: float) -> void:
	if category_interests.has(category):
		var current_interest: float = category_interests[category]
		var new_interest: float = clamp(current_interest + amount, min_interest, max_interest)
		category_interests[category] = new_interest
		print("⭐ Stimulus: ", MarkerCategory.keys()[category], " interest increased by ", snb(amount), " to ", snb(new_interest))

## Applies a negative change to a category's interest level (repulsion).
## Call this externally, e.g., after a negative interaction.
func apply_negative_stimulus(category: int, amount: float) -> void:
	if category_interests.has(category):
		var current_interest: float = category_interests[category]
		# The amount is subtracted to create repulsion/negative interest
		var new_interest: float = clamp(current_interest - amount, min_interest, max_interest) 
		category_interests[category] = new_interest
		print("💥 Stimulus: ", MarkerCategory.keys()[category], " interest decreased by ", snb(amount), " to ", snb(new_interest))

#==============================================================================
# STATE HANDLERS
#==============================================================================

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

func _handle_idle_state() -> void:
	# Decelerate to zero velocity
	velocity.x = lerp(velocity.x, 0.0, 0.1)
	velocity.z = lerp(velocity.z, 0.0, 0.1)

func _handle_walk_state(delta: float, current_speed: float) -> void:
	var target_dir = target_direction 
	var final_speed = current_speed
	
	# 1. POI Tracking (default goal)
	if current_target_poi_node != null:
		var target_position: Vector3 = current_target_poi_node.global_transform.origin
		var direction_to_target: Vector3 = target_position - global_transform.origin
		direction_to_target.y = 0 
		target_dir = direction_to_target.normalized()
		current_target_poi_pos = target_position 
	
	# 2. LEASH LOGIC OVERRIDE (highest priority goal)
	if leash_target_node != null:
		var player_pos = leash_target_node.global_transform.origin
		var walker_pos = global_transform.origin
		var direction_to_player = (player_pos - walker_pos)
		direction_to_player.y = 0
		var distance = direction_to_player.length()

		if distance > leash_rest_length:
			# The leash is taut! Override the direction and speed
			target_dir = direction_to_player.normalized()
			
			# Increase speed to get back quickly
			final_speed = lerp(final_speed, base_speed * 1.5, leash_stiffness)
			
			# Clear the POI goal, as the leash takes priority
			current_target_poi_node = null
			current_target_poi_pos = Vector3.ZERO
			
			print_debug("🔗 Leash TAUT! Overriding direction back to player.")
	
	# 3. Apply movement
	current_movement_direction = current_movement_direction.slerp(target_dir, turn_agility * delta)
	velocity.x = current_movement_direction.x * final_speed
	velocity.z = current_movement_direction.z * final_speed
	
	# 4. STOP-AT-MARKER LOGIC
	if stop_at_marker and current_target_poi_pos != Vector3.ZERO:
		var distance = global_transform.origin.distance_to(current_target_poi_pos)
		
		if distance < STOPPING_DISTANCE:
			current_state = State.IDLE
			state_timer.wait_time = randf_range(min_idle_time, max_idle_time)
			state_timer.start() 
			dir_timer.stop() 
			velocity.x = 0.0
			velocity.z = 0.0
			current_target_poi_pos = Vector3.ZERO
			current_target_poi_node = null
			print("🛑 Reached POI. Transitioning to IDLE.")
			return
	
	# 5. Rotation
	if current_movement_direction.length_squared() > 0.0:
		var flat_direction = current_movement_direction
		flat_direction.y = 0
		if flat_direction.length_squared() > 0.0:
			var target_basis = Basis.looking_at(flat_direction)
			transform.basis = transform.basis.slerp(target_basis, rotation_speed * delta)

#==============================================================================
# POI INTEREST & MOVEMENT LOGIC
#==============================================================================

func _on_dir_timer_timeout() -> void:
	if current_state == State.WALK:
		var walker_position: Vector3 = global_transform.origin
		var total_temptation_score: float = 0.0
		
		# Calculate Temptation Score from ALL other POIs
		for data in waypoint_data:
			var poi_node: Node = data.node
			var poi_pos: Vector3 = poi_node.global_transform.origin
			var category: int = data.category
			
			var interest: float = category_interests.get(category, min_interest)
			
			# POIs with negative or minimum interest don't tempt the walker
			if interest <= min_interest: continue 
			
			var distance: float = max(0.1, walker_position.distance_to(poi_pos))
			
			var distance_factor: float = pow(distance, temptation_distance_influence)
			var temptation_score: float = interest / distance_factor
			
			total_temptation_score += max(0.0, temptation_score) # Only positive temptation

		# Check if the walker succumbs to temptation
		if total_temptation_score > temptation_threshold:
			print("🚨 Target Change: TEMPTED (Score: ", snb(total_temptation_score), "). Picking new goal.")
			_pick_random_direction() 
			return
		
		# Fall back to the old persistence chance check
		if randf() < target_persistence_chance and current_target_poi_node != null:
			return 
		
		# Persistence failed or no goal, so choose a new goal randomly.
		print("🔄 Target Change: Persistence failed/No current goal. Picking new goal.")
		_pick_random_direction()

func _pick_random_direction() -> void:
	# Clear the node reference when picking a random direction
	current_target_poi_node = null
	
	if not waypoint_data.is_empty() and randf() < poi_walk_chance:
		_pick_point_of_interest()
	else:
		var random_angle = randf_range(0, TAU)
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
		var poi_node: Node = data.node                      
		var poi_pos: Vector3 = poi_node.global_transform.origin 
		var category: int = data.category
		data_list.append(data) 
		
		var distance_sq: float = current_pos.distance_squared_to(poi_pos)
		var interest: float = category_interests.get(category, min_interest) # <-- Use Category Interest
		
		# If interest is below minimum (or negative), the weight is 0. 
		if interest <= min_interest:
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
		var chosen_data: Dictionary = data_list[chosen_index]
		var chosen_node: Node = chosen_data.node
		
		current_target_poi_node = chosen_node
		
		var direction_to_poi: Vector3 = chosen_node.global_transform.origin - current_pos
		direction_to_poi.y = 0
		target_direction = direction_to_poi.normalized()
		current_target_poi_pos = chosen_node.global_transform.origin
		
		var category_name = MarkerCategory.keys()[chosen_data.category]
		print("✨ New Target: POI [", category_name, "] named '", chosen_data.name, "' (Interest: ", snb(category_interests[chosen_data.category]), ").")
	else:
		_pick_random_direction()

## Calculates speed based on proximity to the most interesting POI.
func _calculate_dynamic_speed() -> float:
	if current_state == State.IDLE:
		return 0.0

	var walker_position: Vector3 = global_transform.origin
	var max_influence_factor: float = 0.0
	var speed_base: float = base_speed
	
	for data in waypoint_data:
		var poi_node: Node = data.node
		var poi_pos: Vector3 = poi_node.global_transform.origin
		var category: int = data.category
		var current_interest: float = category_interests.get(category, min_interest) # <-- Use Category Interest
		
		if current_interest > 0.0:
			var distance: float = walker_position.distance_to(poi_pos)
			
			if distance < focus_distance:
				var proximity: float = 1.0 - (distance / focus_distance)
				var normalized_interest: float = current_interest / max_interest
				var influence_factor: float = proximity * normalized_interest
				
				max_influence_factor = max(max_influence_factor, influence_factor)

	var calculated_speed = lerp(speed_base, min_focus_speed, max_influence_factor)
	return calculated_speed

## Updates interest levels based on proximity and time.
func _update_waypoint_interests(delta: float) -> void:
	var walker_position: Vector3 = global_transform.origin
	
	var categories_depleted: Array[int] = [] 
	
	# 1. DEPLETION based on proximity to *any* POI
	for data in waypoint_data:
		var category: int = data.category
		
		var poi_node: Node = data.node
		var poi_pos: Vector3 = poi_node.global_transform.origin
		
		var distance: float = walker_position.distance_to(poi_pos)
		
		if distance < depletion_distance:
			# Depletion (Closer = Faster Depletion)
			var proximity_factor: float = 1.0 - (distance / depletion_distance)
			var rate_multiplier: float = lerp(1.0, max_depletion_multiplier, proximity_factor)
			var dynamic_rate: float = depletion_rate * rate_multiplier
			
			var current_interest: float = category_interests.get(category, max_interest)
			current_interest -= dynamic_rate * delta
			
			category_interests[category] = clamp(current_interest, min_interest, max_interest)
			
			if not categories_depleted.has(category):
				categories_depleted.append(category)

	# 2. RESTORATION for categories NOT actively depleted
	for category in category_interests.keys():
		if not categories_depleted.has(category):
			var current_interest: float = category_interests[category]
			
			# Interest can only naturally restore toward max_interest
			if current_interest < max_interest:
				current_interest += restoration_rate * delta
			
			category_interests[category] = clamp(current_interest, min_interest, max_interest)

#==============================================================================
# UTILITY FUNCTIONS
#==============================================================================

## Recursively searches the node tree for Marker3D nodes with the required POI tag.
func _find_tagged_markers_recursive(node: Node, markers: Array) -> void:
	if node is Marker3D and node.has_meta(poi_tag_key):
		var tag_value = node.get_meta(poi_tag_key)
		if tag_value != null and tag_value != false: 
			markers.append(node)
	
	for child in node.get_children():
		_find_tagged_markers_recursive(child, markers)

## Helper function to collect Marker3D positions.
func _populate_points_of_interest(root_node: Node) -> void:
	waypoint_data.clear()
	
	var poi_count = 0
	var category_keys = MarkerCategory.keys()
	
	var tagged_markers: Array = []
	_find_tagged_markers_recursive(root_node, tagged_markers)
	
	for child in tagged_markers:
		var poi_name: String = child.get_meta("poi_name", child.name)
		var type_string: String = str(child.get_meta("poi_type", "GENERAL")).to_upper()
		
		var poi_category: int = MarkerCategory.GENERAL
		var category_index = category_keys.find(type_string)
		
		if category_index != -1:
			poi_category = category_index
		
		waypoint_data.append({
			"node": child,
			"name": poi_name,
			"category": poi_category, 
			"material": null
		}) 
		poi_count += 1

	if poi_count == 0:
		print("⚠️ Warning: RandomWalker found no Marker3D tagged with '", poi_tag_key, "'. Reverting to purely random walk.")
	else:
		print("✅ RandomWalker initialized with ", poi_count, " points of interest using tag '", poi_tag_key, "'.")

## Helper function to simplify number formatting for console output
func snb(number: float) -> String:
	return "%0.2f" % number
