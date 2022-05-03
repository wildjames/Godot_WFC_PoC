extends Node

const TIMER_LIMIT = 2.0
var timer = 0.0

var TileChunk = preload("res://TileChunk.tscn")
var chunks = []


# Called when the node enters the scene tree for the first time.
func _ready():
	var first_pos = Vector2(0,0)
	add_tile_chunk(first_pos)

func _process(delta):
	timer += delta
	if timer > TIMER_LIMIT: # Prints every 2 seconds
		timer = 0.0
		print("fps: " + str(Engine.get_frames_per_second()))

	# Chunk extension 
	# TODO: memory-expensive, switch to creating new chunks.
	var player_node = get_node("Player")
	for chunk in chunks:
		chunk.extend_tilemap()
	
	# Add in new chunks as we near the edge of the map.
	# Changing the position moves the map, but DOESNT move its rect. I'll need to do that myself.
#	var player_node = get_node("Player")
#	var new_chunk_pos : Vector2
#	for chunk in chunks:
#		if chunk.get_rect().has_point(player_node.position):
#			new_chunk_pos = chunk.check_new_map_needed()
#			if new_chunk_pos != Vector2(0,0):
#				print("I want to add a new chunk at ", new_chunk_pos)
##				add_tile_chunk(new_chunk_pos)


func add_tile_chunk(pos):
	print("ADDING A CHUNK")
	var TM = TileChunk.instance()
	add_child(TM)
	chunks.append(TM)
	TM.position = pos
	return TM


func _on_RegenerateMapTimer_timeout():
	for chunk in chunks:
		chunk.refresh_tiles()
