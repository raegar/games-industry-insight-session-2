class_name PlayerToken
extends Node2D

# PlayerToken stores one player's board state and controls its sprite animation.
#
# "@export" makes a variable show up in the Godot Inspector, so each token
# placed in Main.tscn can have its own name, colour, and sprite without
# touching any code. "class_name PlayerToken" (above) lets other scripts
# refer to this type by name, like `if child is PlayerToken`.
@export var player_name: String = "Player"
@export var player_colour: Color = Color.WHITE
@export var tile_index: int = 0
@export var stars_collected: int = 0
@export var lives: int = 3
@export var player_sprite: Texture2D

# TWEAK ME: how long (in seconds) each walking frame shows while a token moves.
# Smaller = faster-shuffling legs, larger = a slow plod. Try 0.1 (fast) or 1.0 (slow) and run!
const STEP_FRAME_TIME := 0.5

# $Name fetches a child node from PlayerToken.tscn. "@onready" waits until
# the scene is fully loaded before looking - otherwise the nodes would not
# exist yet and the game would crash.
@onready var sprite: Sprite2D = $Sprite2D
@onready var label: Label = $NameLabel
@onready var celebration_particles: CPUParticles2D = $CelebrationParticles

var is_moving := false
var moving_animation_time := 0.0

func _ready() -> void:
	update_visuals()


func _draw() -> void:
	# _draw lets a node paint shapes in code. Godot calls it once, then again
	# whenever queue_redraw() is called (see update_visuals below).
	# Drawn underneath the player sprite: a ground shadow plus a coloured glow
	# halo so each token feels lit and clearly belongs to its player.
	draw_circle(Vector2(0, 16), 15.0, Color(0, 0, 0, 0.35))
	var halo := player_colour
	halo.a = 0.30
	draw_circle(Vector2(0, 4), 20.0, halo)
	halo.a = 0.16
	draw_circle(Vector2(0, 4), 28.0, halo)


func _process(delta: float) -> void:
	# _process runs every frame; delta is the time since the previous frame.
	# While moving, switch between the two sprite-sheet frames every
	# STEP_FRAME_TIME seconds.
	if not is_moving:
		return

	moving_animation_time += delta
	# Divide the total time by STEP_FRAME_TIME and keep the remainder of / 2:
	# the answer flips 0, 1, 0, 1... which picks the walking frame.
	sprite.frame = int(moving_animation_time / STEP_FRAME_TIME) % 2


func update_visuals() -> void:
	if not is_node_ready():
		return

	# The player image is a 2-frame horizontal sprite sheet:
	# hframes = 2 splits it into two frames, and frame picks which one shows.
	sprite.texture = player_sprite
	sprite.hframes = 2
	sprite.frame = 0
	# modulate tints the whole sprite with the player's colour.
	sprite.modulate = player_colour
	label.text = player_name
	# Ask Godot to run _draw again so the glow matches the new colour.
	queue_redraw()


func play_celebration() -> void:
	# Fires a one-shot burst of sparkles above the token.
	# GameManager calls this when something good happens, like collecting a star.
	celebration_particles.restart()


func set_moving(value: bool) -> void:
	# GameManager calls this when a glide animation starts or ends.
	is_moving = value
	if not is_moving:
		moving_animation_time = 0.0
		sprite.frame = 0


func reset_for_new_game(start_tile_index: int) -> void:
	# GameManager calls this at the start of every game (and on Reset).
	tile_index = start_tile_index
	stars_collected = 0
	lives = 3
	set_moving(false)
	update_visuals()
