extends KinematicBody2D

var moveSpeed : int = 250

var vel : Vector2 = Vector2()
var facingDir : Vector2 = Vector2()


func _physics_process(delta):
	vel = Vector2()
	
	if Input.is_action_pressed("move_up"):
		vel.y -= 1
		facingDir = Vector2(0, -1)
	
	if Input.is_action_pressed("move_down"):
		vel.y += 1
		facingDir = Vector2(0, +1)

	if Input.is_action_pressed("move_left"):
		vel.x -= 1
		facingDir = Vector2(-1, 0)

	if Input.is_action_pressed("move_right"):
		vel.x += 1
		facingDir = Vector2(1, 0)
	
	vel = vel.normalized()
	move_and_slide(vel * moveSpeed)
