extends TileMap


# Random number generator
var rng = RandomNumberGenerator.new()
# How many tile IDs I have
var num_tiles = 3
var uncollapsed_ID = 0

# 'Anything' represents a FULLY uncertain state
var anything = int(pow(2, num_tiles + 1) - 2)
var all_forbidden = 0

# Will be initialised with every cell being in all states. Keyed by Vector2.
# A 2D array will almost CERTAINLY be faster, but will need extra logic to track 
# a growing map, or additional chunks. 
var cell_superpositions = {}
# Track the entropy of all cells. Keyed by Vector2
var cell_entropies = {}

# My rules! These are the numbers corresponding to allowed neighbours
# 0: Cell collapse flag
# 1: Grass
# 2: Sand
# 3: Water
# 4: Walls
# 5: Corners
var allowed_neighbours : PoolByteArray = [
	0x36, # Grass tile, 00110110
	0x3E, # Sand tile,  00111110
	0x3C, # Water tile, 00111100
	0x3E, # Walls
	0x3E, # Corners
]

# The weights for each possible neighbour, for each tile type
# In order, so [grass_weight, sand_weight, water_weight]. Must sum to 1.0
var tile_weights = [
	40, # Grass
	5,  # Sand
	60, # Water
]

# These are vectors that point to a cells neighbours
var cardinal_directions = [
	Vector2( 0,  1),
	Vector2( 0, -1),
	Vector2( 1,  1),
	Vector2( 1,  0),
	Vector2( 1, -1),
	Vector2(-1,  1),
	Vector2(-1,  0),
	Vector2(-1, -1),
]


# Called when the node enters the scene tree for the first time.
func _ready():
	randomize()
	
	var all_cells = get_used_cells()
	var cell_state : int
	for cell in all_cells:
		cell_state = get_cell(cell.x, cell.y)
		
		# If we're a collapsed cell, set the appropriate superposition.
		if cell_state > 0:
			cell_superpositions[cell] = (1 << cell_state) + 1
			cell_entropies[cell] = 0.0
		else:
			cell_superpositions[cell] = anything
			cell_entropies[cell] = 1.0

	update_all_superpositions()


func _input(event):
	# Mouse in viewport coordinates.
	if event is InputEventMouseButton:
		if event.is_pressed():
			collapse_next()


func _physics_process(delta):
	if Input.is_action_just_pressed("test_scene_playpause"):
		var gopher_timer = get_node("GopherTimer")
		if gopher_timer.is_stopped():
			gopher_timer.start()
		else:
			gopher_timer.stop()
	pass


func _on_Timer_timeout():
	collapse_next()


func sum(arr:Array):
	var result = 0
	for i in arr:
		result+=i
	return result

# My gut says this could be a shader - but I don't know how well they'd interact 
# if the cells are updated asynchronously... It could be problematic?
# Note that I've left the debugging print statements deliberately commented, rather than removed. 
# I anticipate problems when I add more complex rules!!
func update_cell_superposition(cell):
#	print("\n-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=")
#	print("I am updating the possible states of the cell at (%d, %d)" % [cell.x, cell.y])
	if not cell_superpositions.has(cell):
#		print("That cell isn't in the dict, initialising as anything and computing it...")
		cell_superpositions[cell] = anything
		cell_entropies[cell] = 0.0
	
	var other : Vector2
	var other_superposition : int
	
	var new_superposition = ~anything
	
	var forbidden_states = []
	var state : int
	
	# Don't update collapsed cells (disabled for testing)
	if cell_superpositions[cell] & 1:
#		print("Cell is already collapsed, returning superposition %d" % [cell_superpositions[cell]])
		return cell_superpositions[cell]
	
	for vect in cardinal_directions:
		other = cell + vect
		if cell_superpositions.has(other):
			other_superposition = cell_superpositions[other]
		else:
			other_superposition = anything
		
#		print("Checking against my neighbour at (%d, %d)" % [other.x, other.y])
#		print("Other has a superposition state of %d" % [other_superposition])
#		print("It is using the tile %d" % [get_cell(other.x, other.y)])
#		print("Checking for an intersection between rulesets, and this superposition")
		
		state = 0
		for ruleset in allowed_neighbours:
			# The ruleset is a list of allowed neighbour states. 
			# If other_superposition and the ruleset intersect, this state is allowed!
			
#			print("Ruleset: ", ruleset)
			
			if not (ruleset & other_superposition):
#				print("Neighbour superposition of %d has no intersection with ruleset %d" % [other_superposition, ruleset])
				
				forbidden_states.append(state)
				
#				print("Forbidden states is now: ", forbidden_states)
				
				new_superposition |= (1 << (state+1))
				if ~new_superposition == all_forbidden:
					print("ALL STATES ARE FORBIDDEN!")
					return anything
				
			state += 1

#		print("Okay, done checking this neighbour.")
#		print("")
	
	new_superposition = ~new_superposition
	
	cell_superpositions[cell] = new_superposition
	update_cell_entropy(cell)

#	print("\n --> Done with this cell")
#	print("My new superposition is %d" % [new_superposition])
	return new_superposition


func collapse_cell_state(loc):
	# Returns the state of the cell, if collapsed. 
	# Returns 0 if the cell was already collapsed.
	# Returns -1 if the cell is unable to be collapsed, and sets its superposition to allow all states.
	
	var NextCell = get_node("NextCell")
	NextCell.position = map_to_world(loc) + (cell_size/4)
	update()
	
	if cell_superpositions[loc] & 1:
		return 0
	
	var cell_superposition = update_cell_superposition(loc)
	
	var possible_bits = []
	var new_byte : int
	
	# If the LSB is set, this cell is already collapsed
	if cell_superposition == 0:
		print("--> INVALID SUPERPOSITION!!!")
		cell_superpositions[loc] = anything
		return -1
	
	# Get a list of possible states
	var sum_of_weights = 0.0
	for i in range(1, num_tiles+1):
		new_byte = cell_superposition >> i
		if new_byte & 1:
			possible_bits.append(i)
			sum_of_weights += tile_weights[i-1]
	
	# Unweighted selection
#	possible_bits.shuffle()
#	var state = possible_bits[0]
	
	# Weighted state selection
	var state : int
	var rand_num = rng.randf() * sum_of_weights
	for i in possible_bits:
		if rand_num < tile_weights[i-1]:
			state = i
			break
		rand_num -= tile_weights[i-1]
	
	set_cell(loc.x, loc.y, state)
	
	# Update my cell superposition to reflect my collapse
	cell_superposition = (1 << state) + 1
	cell_superpositions[loc] = cell_superposition
	
	# Recalculate my entropy, and the entropies of the cells around me
	cell_entropies[loc] = update_cell_entropy(loc)
	for vect in cardinal_directions:
		cell_superpositions[loc+vect] = update_cell_superposition(loc+vect)
	
	return state


func collapse_all():
	while collapse_next() > 0:
		pass
	return


func collapse_next():
	var target_cell : Vector2
	var all_cells = get_used_cells()
	all_cells.shuffle()

	# Choose a random possible entropy, *weighted by those entropies*, and collapse a cell with it. 
	var possible_entropies = []
	var possible_weights = []
	var sum_weights = 0.0
	var num_entropies = 0
	var this_entropy : float
	for cell in all_cells:
		if cell_entropies[cell] != 0:
			this_entropy = cell_entropies[cell]
			
			if not possible_entropies.has(this_entropy):
				num_entropies += 1
				sum_weights += this_entropy
				possible_entropies.append(this_entropy)
				possible_weights.append(1.0/(this_entropy*this_entropy))
	
	# Catch the case where I'm fully collapsed
	if possible_weights.size() == 0:
		return 0
		
	var rand_num = rng.randf_range(0.0, sum_weights)
	var target_entropy = 0.0
	for i in range(num_entropies):
		if possible_weights[i] > rand_num:
			target_entropy = possible_entropies[i]
			break
		rand_num -= possible_weights[i]
	
	for cell in all_cells:
		if cell_entropies[cell] == target_entropy:
			target_cell = cell
			break

#	print("Collapsing cell at (%d, %d), which is currently in superposition %d and has entropy %.3f\n\n" % [target_cell.x, target_cell.y, cell_superpositions[target_cell], cell_entropies[target_cell]])
	return collapse_cell_state(target_cell)


func update_cell_entropy(cell):
#	var shannon_entropy_for_square = log(sum(weight)) - (sum(weight * log(weight)) / sum(weight))
	var entropy : float = 0.0
	var cell_superposition = cell_superpositions[cell]
	
	if not (cell_superposition & 1):
		for i in range(1, num_tiles+1):
			if (cell_superposition >> i) & 1:
				entropy -= tile_weights[i-1] * log(tile_weights[i-1])

		
	cell_entropies[cell] = entropy

	return entropy


func update_all_superpositions():
	var all_cells = get_used_cells()
	var cell_ID : int
	
	for cell in all_cells:
		cell_ID = get_cell(cell.x, cell.y)
		if cell_ID != -1:
			update_cell_superposition(cell)
