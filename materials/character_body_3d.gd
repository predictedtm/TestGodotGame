class_name RandomWalker
extends CharacterBody3D

@export_group("Movement Settings")
## The original speed is now the base/maximum speed.
@export var base_speed: float = 3.0 
## Minimum speed when near max interest POI.
@export var min_focus_speed: float = 1.0 
## The distance (radius) within which speed starts to decrease.
@export var focus_distance: float = 5.0 
## How fast the character visually turns. Higher is faster.
@export var rotation_speed: float = 5.0
## How sharply the character changes its movement path. Lower values create wider, more circular turns.
@export var turn_agility: float = 3.0
## Gravity applied to the character.
@export var gravity: float = 9.8

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
@export var poi_walk_chance: float = 0.5
@export var time_for_target_reconsideration: float = 0.5
@export var target_persistence_chance: float = 0.9 
@export var temptation_threshold: float = 1.0 
@export var temptation_distance_influence: float = 2.0 
## The NodePath to a Node3D containing all the Marker3D waypoints.
@export var waypoints_container_path: NodePath 

@export_group("POI Interest Settings")
@export var max_interest: float = 1.0
@export var restoration_rate: float = 0.1
@export var depletion_rate: float = 1.0 
@export var depletion_distance: float = 2.0
@export var max_depletion_multiplier: float = 5.0 


# Stores waypoint data: [{ "pos": Vector3, "material": StandardMaterial3D }, ...]
var waypoint_data: Array[Dictionary] = [] 
# Dictionary to track interest: {Vector3 (position) : float (interest_level)}
var poi_interests: Dictionary = {}

enum State { IDLE, WALK }

var current_state: State = State.IDLE
var target_direction: Vector3 = Vector3.FORWARD
var current_movement_direction: Vector3 = Vector3.FORWARD
var current_target_poi_pos: Vector3 = Vector3.ZERO # Track the current POI goal for logging

@onready var state_timer: Timer = $StateTimer
@onready var dir_timer: Timer = $DirectionTimer


func _ready() -> void:
	if waypoints_container_path and get_node(waypoints_container_path):
		_populate_points_of_interest(get_node(waypoints_container_path))
	
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


## Calculates speed based on proximity to the most interesting POI.
func _calculate_dynamic_speed() -> float:
	var walker_position: Vector3 = global_transform.origin
	var max_influence_factor: float = 0.0
	
	for data in waypoint_data:
		var poi_pos: Vector3 = data.pos
		var current_interest: float = poi_interests.get(poi_pos, 0.0)
		
		if current_interest > 0.0:
			var distance: float = walker_position.distance_to(poi_pos)
			
			if distance < focus_distance:
				var proximity: float = 1.0 - (distance / focus_distance)
				var normalized_interest: float = current_interest / max_interest
				var influence_factor: float = proximity * normalized_interest
				
				max_influence_factor = max(max_influence_factor, influence_factor)
				
	var calculated_speed = lerp(base_speed, min_focus_speed, max_influence_factor)

	# LOG: Speed change
	if abs(calculated_speed - base_speed) > 0.01:
		print("🦥 Speed reduced to: ", snb(calculated_speed), " (Influence: ", snb(max_influence_factor), ")")
	
	return calculated_speed


## Helper function to collect Marker3D positions and initialize interest.
func _populate_points_of_interest(container: Node) -> void:
	waypoint_data.clear()
	poi_interests.clear()
	
	var poi_count = 0
	for child in container.get_children():
		if child is Marker3D:
			var pos: Vector3 = child.global_transform.origin
			
			# NOTE: Material/Mesh logic removed. Only storing position for movement/interest.
			waypoint_data.append({"pos": pos, "material": null}) 
			poi_interests[pos] = max_interest 
			poi_count += 1
	
	if poi_count == 0:
		print("⚠️ Warning: RandomWalker found no Marker3D waypoints under the specified path. Reverting to purely random walk.")
	else:
		print("✅ RandomWalker initialized with ", poi_count, " points of interest.")


## Helper function to continuously update the interest level 
func _update_waypoint_interests(delta: float) -> void:
	var walker_position: Vector3 = global_transform.origin
	
	for data in waypoint_data:
		var poi_pos: Vector3 = data.pos
		
		var current_interest: float = poi_interests.get(poi_pos, 0.0)
		var old_interest: float = current_interest
		
		if current_interest == 0.0 and not poi_interests.has(poi_pos):
			poi_interests[poi_pos] = max_interest
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
		poi_interests[poi_pos] = current_interest
		
		# LOG: Interest Change
		if abs(old_interest - current_interest) > 0.001:
			var change_amount = abs(old_interest - current_interest)
			if (interest_change_type == "Depleted" and change_amount > 0.01) or (interest_change_type == "Restored" and change_amount > 0.05):
				print("🎯 POI Interest ", interest_change_type, " (Dist:", snb(distance), "): ", snb(old_interest), " -> ", snb(current_interest))


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
	current_movement_direction = current_movement_direction.slerp(target_direction, turn_agility * delta)
	velocity.x = current_movement_direction.x * current_speed
	velocity.z = current_movement_direction.z * current_speed
	
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
			var poi_pos: Vector3 = data.pos
			var interest: float = poi_interests.get(poi_pos, 0.0)
			
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
			# LOG: Stayed persistent
			# If current_target_poi_pos is not Vector3.ZERO, it's a POI goal.
			if current_target_poi_pos != Vector3.ZERO:
				pass # Too frequent to log, but logic is fine.
			return 
		
		# Persistence failed, no high temptation, so choose a new goal randomly.
		print("🔄 Target Change: Persistence failed. Picking new goal.")
		_pick_random_direction()


func _pick_random_direction() -> void:
	if not waypoint_data.is_empty() and randf() < poi_walk_chance:
		_pick_point_of_interest()
	else:
		var random_angle = randf_range(0, TAU)
		target_direction = Vector3(sin(random_angle), 0, cos(random_angle)).normalized()
		current_target_poi_pos = Vector3.ZERO
		print("🧭 New Direction: Random Walk.")


func _pick_point_of_interest() -> void:
	var current_pos: Vector3 = global_transform.origin
	var total_weight: float = 0.0
	var positions: Array[Vector3] = [] 
	var weights: Array[float] = []
	
	var min_distance_sq: float = 0.01 

	for data in waypoint_data:
		var poi_pos: Vector3 = data.pos
		positions.append(poi_pos)
		
		var distance_sq: float = current_pos.distance_squared_to(poi_pos)
		var interest: float = poi_interests.get(poi_pos, 0.0) 
		
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
		var chosen_poi: Vector3 = positions[chosen_index] 
		var direction_to_poi: Vector3 = chosen_poi - current_pos
		
		direction_to_poi.y = 0
		target_direction = direction_to_poi.normalized()
		current_target_poi_pos = chosen_poi
		print("✨ New Direction: POI Target (Weight: ", snb(weights[chosen_index]), ", Total: ", snb(total_weight), ").")
	else:
		_pick_random_direction()


## Helper function to simplify number formatting for console output
func snb(number: float) -> String:
	return "%0.2f" % number
