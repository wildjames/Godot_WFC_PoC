extends TileMap


# Random number generator
var rng = RandomNumberGenerator.new()
# How many tile IDs I have
var num_tiles = 3
var uncollapsed_ID = 3

var map_build_ahead_fraction = 1.3

# Tiles in this range are static, and get fully collapsed
var collapsed_radius = 10
# Tiles in this range fluctuate
var update_radius = 15


# These variables say if I have neighbours to each side:
var has_left = false
var has_right = false
var has_bottom = false
var has_top = false


# Store the possible cell states, based on their surroundings
# The superposition is stored as an array of 32 bit byte arrays. There are 3 options.
# Each bit will represent the possibility of this tile being in a particular state.
# The LSB represents if the cell has been collapsed or not. 1 for collapsed, 0 for not.
var cell_superpositions = {}

# My rules! These are the numbers corresponding to allowed neighbours
var allowed_neighbours = [
	[], # flag for collapsed state, no rules here
	[1, 3], # water tile
	[2, 3], # Grass tile
	[1, 2, 3], # sand tile
]

var cardinal_directions = [
	Vector2( 1,  1),
	Vector2( 1,  0),
	Vector2( 1, -1),
	Vector2(-1,  1),
	Vector2(-1,  0),
	Vector2(-1, -1),
	Vector2( 0,  1),
	Vector2( 0, -1),
]


# Called when the node enters the scene tree for the first time.
func _ready():
	set_name(str("%d_%d" % [self.position[0], self.position[1]]))
	
	rng.randomize()
	
	extend_tilemap()
	
	# Initialise all my cells as in a maximal superposition. 
	var all_visible_tiles = get_used_cells()
	var state : int
	for cell in all_visible_tiles:
		state = get_cell(cell.x, cell.y)
		if state == uncollapsed_ID:
			cell_superpositions[cell] = int(pow(2, num_tiles + 1) - 2)
		else:
			cell_superpositions[cell] = (1 << state) + 1
#			print("Cell at %d, %d is already defined as %d" % [cell.x, cell.y, state])
#			print("Setting superposition to %d" % [cell_superpositions[cell]])
	
	update_all_cell_superpositions()
	
	# If the player is on my tiles, collapse their cell. 
	var player_vec = get_node("../Player").position
	var player_loc = world_to_map(player_vec)
	collapse_cell(player_loc)
	for i in range(collapsed_radius):
		collapse_annulus(player_loc, i)



# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
#	alter_tile_at_mouse()
	pass
	

func get_rect():
	var cell_bounds = get_used_rect()
	var cell_to_px = Transform2D(Vector2(cell_size.x * scale.x, 0), Vector2(0, cell_size.y * scale.y), Vector2())

	return Rect2(cell_to_px * cell_bounds.position, cell_to_px * cell_bounds.size)


func check_new_map_needed():
	# Get the canvas transform
	var ctrans = get_canvas_transform()
	# The canvas transform applies to everything drawn,
	# so scrolling right offsets things to the left, hence the '-' to get the world position.
	# Same with zoom so we divide by the scale.
	var min_pos = -ctrans.get_origin() / ctrans.get_scale()
	# The maximum edge is obtained by adding the rectangle size.
	# Because it's a size it's only affected by zoom, so divide by scale too.
	var view_size = get_viewport_rect().size / ctrans.get_scale()
	var padding_margins = view_size * map_build_ahead_fraction / 2
	
	min_pos = min_pos - padding_margins
	view_size = view_size + padding_margins
	
	var vp_rect = Rect2(min_pos, view_size)
	
	# Getting my own rect is easy. This is in "real units", of world coordinates
	var my_rect = get_rect()
	
	if not my_rect.encloses(vp_rect):
		# Check the left
		if vp_rect.position[0] < my_rect.position[0]:
			var new_TM_position = my_rect.position
			new_TM_position[0] -= my_rect.size[0]
			self.has_left = true
			return new_TM_position

	return Vector2(0,0)


# See if the player viewport limits are outside the edge of this tilemap.
# If I can see beyond the edge, fill in the void by extending this tilemap.
# This is REALLY sloppy! But not my focus, I'll fix it later.
func extend_tilemap():
	# Get the canvas transform
	var ctrans = get_canvas_transform()
	# The canvas transform applies to everything drawn,
	# so scrolling right offsets things to the left, hence the '-' to get the world position.
	# Same with zoom so we divide by the scale.
	var min_pos = -ctrans.get_origin() / ctrans.get_scale()
	# The maximum edge is obtained by adding the rectangle size.
	# Because it's a size it's only affected by zoom, so divide by scale too.
	var view_size = get_viewport_rect().size / ctrans.get_scale()
	var padding_margins = view_size * map_build_ahead_fraction / 2
	
	min_pos = min_pos - padding_margins
	view_size = view_size + padding_margins
	
	var vp_rect = Rect2(min_pos, view_size)
	
	
	# Getting my own rect is easy
	var my_rect = get_rect()
	
	# Now I loop over the cells, starting with the outer perimiter and checking for empties.
	# If I find at least one, fill it/them in. If I dont, then assume the map is filled and stop 
	#	checking
	if not my_rect.encloses(vp_rect):
		var min_x = min_pos[0] / cell_size.x
		var min_y = min_pos[1] / cell_size.y
		var max_x = (min_pos[0] + view_size[0]) / cell_size.x
		var max_y = (min_pos[1] + view_size[1]) / cell_size.y
		
		var found_empty : bool
		var this_cell : int
		for loop_i in range(0, min(max_x-min_x, max_y-min_y)):
			found_empty = false
			
			# Do the top and bottom
			for x in range(min_x + loop_i, max_x - loop_i):
				for y in [min_y + loop_i, max_y - loop_i]:
					this_cell = get_cell(x, y)
					if this_cell == -1:
						set_cell(x, y, uncollapsed_ID)
						cell_superpositions[Vector2(x, y)] = int(pow(2, num_tiles + 1) - 2)
						found_empty = true
					
			# Do the left and right
			for y in range(min_y + loop_i, max_y - loop_i):
				for x in [min_x + loop_i, max_x - loop_i]:
					this_cell = get_cell(x,y)
					if this_cell == -1:
						set_cell(x, y, uncollapsed_ID)
						cell_superpositions[Vector2(x, y)] = int(pow(2, num_tiles + 1) - 2)
						found_empty = true
#			if not found_empty:
##				print("I found no empty cells on loop %d" % loop_i)
#				return


# Cell is the cell vector
func get_crow_distance_to_player(cell) -> int:
	var player_vec = get_node("../Player").position
	var sep_vec = player_vec - map_to_world(cell)
	var dist = int(sep_vec.length())
	
	return dist


func get_taxi_distance_to_player(cell) -> int:
	var loc = world_to_map(get_node("../Player").position)
	var sep_vec = cell - loc
	var dist = abs(sep_vec[0]) + abs(sep_vec[1])
	return dist


func update_cell_superposition(cell):
	print("I am updating the possible states of the cell at (%d, %d)" % [cell.x, cell.y])
	var other : Vector2
	var other_superposition : int
	var new_superposition = ~ int(pow(2, num_tiles + 1) - 2)
	
	var forbidden_states = []
	var is_allowed : bool
	var state : int
	
	for vect in cardinal_directions:
		other = cell + vect
		other_superposition = cell_superpositions[other]
		print("Checking against my neighbour at (%d, %d)" % [other.x, other.y])
		print("Other has a superposition state of %d" % [other_superposition])
		print("It is using the tile %d" % [get_cell(other.x, other.y)])
		
		print("Checking for an intersection between rulsets, and this superposition")
		is_allowed = true
		state = 1
		for ruleset in allowed_neighbours:
			# The ruleset is a list of allowed neighbour states. 
			# If other_superposition and the ruleset intersect, this state is allowed!
			print("Ruleset: ", ruleset)
			
			if not (ruleset & other_superposition):
#				print("Neighbour superposition of %d has no intersection with ruleset %d" % [other_superposition, ruleset])
				forbidden_states.append(state)
				new_superposition |= (1 << state)
#				print("Forbidden states is now: ", forbidden_states)
				
			state += 1

#		print("Okay, done checking this neighbour. Is it allowed? %s \n" % [is_allowed])
#		print("")
	
	new_superposition = ~new_superposition
#	print("\n --> Done with this cell")
#	print("My new superposition is %d" % [new_superposition])
	return new_superposition


func update_annulus_cell_superpositions(center, radius):
	var min_x = center[0] - radius
	var max_x = center[0] + radius
	var min_y = center[1] - radius
	var max_y = center[1] + radius
	
	var cell : Vector2
	var cell_superposition : int

	for x in range(min_x, max_x+1):
		for y in [min_y, max_y+1]:
			cell = Vector2(x, y)
			update_one_cell_superposition(cell)
	for y in range(min_y+1, max_y+1):
		for x in [min_x, max_x]:
			cell = Vector2(x, y)
			update_one_cell_superposition(cell)


func update_all_cell_superpositions():
#	var player_vec = get_node("../Player").position
#	var player_loc = world_to_map(player_vec)
#
#	for ring in range(collapsed_radius, update_radius):
#		update_annulus_cell_superpositions(player_loc, ring)

	update_annulus_cell_superpositions(Vector2(0,0), 1)



func collapse_cell_state(loc):
	var cell_superposition = update_cell_superposition(loc)
	
	var possible_bits = []
	var new_byte : int
	var state = 0
	
	# If the LSB is set, this cell is already collapsed
#	if cell_superposition & 1:
#		print("Cell %d, %d is already collapsed!" % [loc.x, loc.y])
#		return
	if cell_superposition == 0:
		print("FUCK, invalid superposition!!!")
	
	# Get a list of possible states
	for i in range(1, num_tiles+1):
		new_byte = cell_superposition >> i
		if new_byte & 1:
			possible_bits.append(i)
	
	state = possible_bits[rng.randi() % possible_bits.size()] - 1
	print("From possible states: ", possible_bits, ", I chose %d" % [state])
	
	set_cell(loc.x, loc.y, state)
	print("The new SP state is then %d" % [1 << int((state+1) + 1)])
	
	cell_superposition = (1 << (state)) | 1
	cell_superpositions[loc] = cell_superposition
	
	return cell_superposition


func collapse_annulus(center, radius):
	var min_x = center[0] - radius
	var max_x = center[0] + radius
	var min_y = center[1] - radius
	var max_y = center[1] + radius
	
	var cell : Vector2
	var cell_superposition : int

	for x in range(min_x, max_x+1):
		for y in [min_y, max_y+1]:
			cell = Vector2(x, y)
			collapse_cell(cell)
	for y in range(min_y+1, max_y+1):
		for x in [min_x, max_x]:
			cell = Vector2(x, y)
			collapse_cell(cell)


# For now, if a cell is uncollapsed just set it to a reserved "undecided" tile
func fluctuate_cell(cell):
	var cell_superposition : int
	if cell_superpositions.has(cell):
		cell_superposition = cell_superpositions[cell]
	else:
		# Fail towards the side of caution, but raise a message about it
		cell_superposition = int(pow(2, num_tiles+1)) - 2

	# If the LSB is set, this cell is already collapsed
	if not (cell_superposition & 1):
		set_cell(cell.x, cell.y, rng.randi_range(0, num_tiles-1))


func fluctuate_annulus(center, radius):
	var min_x = center[0] - radius
	var max_x = center[0] + radius
	var min_y = center[1] - radius
	var max_y = center[1] + radius
	
	var cell : Vector2
	var cell_superposition : int

	for x in range(min_x, max_x+1):
		for y in [min_y, max_y+1]:
			cell = Vector2(x, y)
			fluctuate_cell(cell)
	for y in range(min_y+1, max_y+1):
		for x in [min_x, max_x]:
			cell = Vector2(x, y)
			fluctuate_cell(cell)


func refresh_tiles():
	var player_vec = get_node("../Player").position
	var player_loc = world_to_map(player_vec)
	
	update_all_cell_superpositions()
	
	var all_visible_tiles = get_used_cells()
	var dist : int
#	print("I have %d visible tiles." % len(all_visible_tiles))

	# These cells get flipped between their states
	for i in range(collapsed_radius, update_radius):
		fluctuate_annulus(player_loc, i)
			
	for i in range(collapsed_radius):
		collapse_annulus(player_loc, i)
