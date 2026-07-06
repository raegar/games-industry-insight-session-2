class_name BoardPosition
extends Node2D

# A BoardPosition is one square on the board.
# It knows how it should look, what effect it has, and when the mouse clicks it.
#
# Signals are how nodes talk to each other in Godot. This tile "emits" a
# signal (like shouting "I was clicked!") and the GameManager listens for it.
# The tile never needs to know who is listening - that keeps the code tidy.
signal selected(board_position: BoardPosition)
signal hovered(board_position: BoardPosition)
signal hover_ended(board_position: BoardPosition)

# These are the different kinds of board squares students can choose from.
enum TileType {
	NORMAL,
	MOVE_FORWARD,
	JUMP,
	SWAP_PLAYERS,
	GAIN_LIFE,
	HAZARD
}

# This number decides the order players travel around the board.
@export var tile_index: int = 0

# This is the default tile type
# The "set(value):" block is a setter - it runs every time the value changes
# (even from the editor Inspector), so the tile instantly redraws itself.
@export var tile_type: TileType = TileType.NORMAL:
	set(value):
		tile_type = value
		update_visuals()

# Used when tile_type is MOVE_FORWARD.
@export var move_forward_amount: int = 0:
	set(value):
		move_forward_amount = value
		update_visuals()

# Used when tile_type is JUMP.
@export var jump_target_index: int = 0:
	set(value):
		jump_target_index = value
		update_visuals()

# Turn this on in the 2D editor to place a collectible star on this board position.
@export var has_star_token: bool = false:
	set(value):
		has_star_token = value
		update_visuals()

var star_collected := false
var is_selected_for_swap := false

# These variables are shortcuts to child nodes in BoardPosition.tscn.
# The $ symbol means "find a child node with this name".
@onready var icon_sprite: Sprite2D = $IconSprite
@onready var star_sprite: Sprite2D = $StarSprite
@onready var label: Label = $TileLabel
@onready var click_area: Area2D = $ClickArea

# The tile background is now drawn in code (see _draw) instead of using a
# picture file. This gives every square rounded corners, depth and a neon glow.
const TILE_SIZE := Vector2(92, 92)
const CORNER_RADIUS := 18
const STAR_GLOW := Color(1.0, 0.85, 0.35)
const STAR_TEXTURE := preload("res://assets/sprites/star.png")

# Each tile type gets its own colour scheme: a dark "base" fill and a bright
# neon "accent" used for the border and the glow around the square.
const TILE_PALETTES := {
	TileType.NORMAL: {"base": Color(0.12, 0.16, 0.30), "accent": Color(0.45, 0.65, 1.0)},
	TileType.MOVE_FORWARD: {"base": Color(0.07, 0.22, 0.20), "accent": Color(0.25, 0.95, 0.70)},
	TileType.JUMP: {"base": Color(0.16, 0.10, 0.30), "accent": Color(0.72, 0.45, 1.0)},
	TileType.SWAP_PLAYERS: {"base": Color(0.24, 0.10, 0.26), "accent": Color(1.0, 0.45, 0.85)},
	TileType.GAIN_LIFE: {"base": Color(0.09, 0.22, 0.13), "accent": Color(0.45, 1.0, 0.55)},
	TileType.HAZARD: {"base": Color(0.28, 0.08, 0.12), "accent": Color(1.0, 0.42, 0.42)}
}

# Icons sit on top of the square and show the tile's effect.
const ICON_TEXTURES := {
	TileType.NORMAL: null,
	TileType.MOVE_FORWARD: preload("res://assets/sprites/icon_move.png"),
	TileType.JUMP: preload("res://assets/sprites/icon_jump.png"),
	TileType.SWAP_PLAYERS: preload("res://assets/sprites/icon_swap.png"),
	TileType.GAIN_LIFE: preload("res://assets/sprites/icon_life.png"),
	TileType.HAZARD: preload("res://assets/sprites/icon_hazard.png")
}

func _ready() -> void:
	# Connect mouse events from the Area2D so this tile can be clicked and hovered.
	click_area.input_event.connect(_on_click_area_input_event)
	click_area.mouse_entered.connect(_on_click_area_mouse_entered)
	click_area.mouse_exited.connect(_on_click_area_mouse_exited)
	# Give the tile number a soft outline so it stays readable on any colour.
	label.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	label.add_theme_constant_override("outline_size", 4)
	update_visuals()


func _process(_delta: float) -> void:
	# Only animated tiles (a waiting star or a selected square) need to repaint
	# every frame, so we keep the rest still to stay efficient.
	if is_selected_for_swap or (has_star_token and not star_collected):
		queue_redraw()


func _draw() -> void:
	# This draws the rounded, glowing square. Children (icon, star, number) are
	# drawn on top of this automatically.
	var palette: Dictionary = TILE_PALETTES.get(tile_type, TILE_PALETTES[TileType.NORMAL])
	var base: Color = palette["base"]
	var accent: Color = palette["accent"]
	var rect := Rect2(-TILE_SIZE * 0.5, TILE_SIZE)
	var time := float(Time.get_ticks_msec()) * 0.001

	# 1. A soft drop shadow makes the tile feel like it floats above the board.
	var drop := StyleBoxFlat.new()
	drop.bg_color = Color(0, 0, 0, 0.45)
	drop.set_corner_radius_all(CORNER_RADIUS)
	drop.shadow_color = Color(0, 0, 0, 0.4)
	drop.shadow_size = 9
	drop.shadow_offset = Vector2(0, 7)
	draw_style_box(drop, rect)

	# 2. The glow colour. Tiles with a waiting star pulse gold to draw the eye.
	var glow_color := accent
	var glow_size := 6
	if has_star_token and not star_collected:
		glow_color = STAR_GLOW
		glow_size = int(9.0 + sin(time * 3.0) * 4.0)

	# 3. The main body of the tile: dark fill, bright border, neon glow.
	var body := StyleBoxFlat.new()
	body.bg_color = base
	body.set_corner_radius_all(CORNER_RADIUS)
	body.set_border_width_all(2)
	body.border_color = accent.lightened(0.15)
	body.shadow_color = Color(glow_color, 0.55)
	body.shadow_size = glow_size
	body.shadow_offset = Vector2.ZERO
	body.anti_aliasing = true
	draw_style_box(body, rect)

	# 4. A faint sheen across the top gives the square a glossy finish.
	var sheen := StyleBoxFlat.new()
	sheen.bg_color = Color(1, 1, 1, 0.07)
	sheen.set_corner_radius_all(CORNER_RADIUS - 4)
	var sheen_rect := Rect2(rect.position + Vector2(6, 6), Vector2(TILE_SIZE.x - 12, TILE_SIZE.y * 0.42))
	draw_style_box(sheen, sheen_rect)

	# 5. While picked for a swap, a bright cyan ring pulses around the tile.
	if is_selected_for_swap:
		var pulse := 0.5 + 0.5 * sin(time * 6.0)
		var ring := StyleBoxFlat.new()
		ring.draw_center = false
		ring.set_corner_radius_all(CORNER_RADIUS + 3)
		ring.set_border_width_all(3)
		ring.border_color = Color(0.6, 0.95, 1.0, 0.6 + 0.4 * pulse)
		ring.shadow_color = Color(0.5, 0.9, 1.0, 0.4 * pulse)
		ring.shadow_size = 8
		draw_style_box(ring, rect.grow(4.0))


func _on_click_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	# Only react to a left mouse button being pressed down
	# (not released, not right-click, not mouse movement).
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# emit(self) shouts "I was clicked!" and passes this tile along,
		# so the GameManager knows exactly which square it was.
		selected.emit(self)


func _on_click_area_mouse_entered() -> void:
	hovered.emit(self)


func _on_click_area_mouse_exited() -> void:
	hover_ended.emit(self)


func get_swappable_data() -> Dictionary:
	# Only the tile effect data is swappable.
	# The tile number, position, and star token stay where they are.
	return {
		"tile_type": tile_type,
		"move_forward_amount": move_forward_amount,
		"jump_target_index": jump_target_index
	}


func apply_swappable_data(data: Dictionary) -> void:
	tile_type = data["tile_type"]
	move_forward_amount = data["move_forward_amount"]
	jump_target_index = data["jump_target_index"]
	update_visuals()


func collect_star() -> bool:
	# Returns true only if a star was actually collected this time.
	if has_star_token and not star_collected:
		star_collected = true
		update_visuals()
		return true
	return false


func set_swap_selected(value: bool) -> void:
	is_selected_for_swap = value
	update_visuals()


func get_action_name() -> String:
	# Turns the tile type into friendly text for tooltips and messages.
	# "match" checks one value against several options, like a tidy if/elif chain.
	match tile_type:
		TileType.NORMAL:
			return "Quiet Space"
		TileType.MOVE_FORWARD:
			return "Boost +%d" % move_forward_amount
		TileType.JUMP:
			return "Portal to %d" % jump_target_index
		TileType.SWAP_PLAYERS:
			return "Swap Players"
		TileType.GAIN_LIFE:
			return "Gain Life"
		TileType.HAZARD:
			return "Hazard"
	return "Unknown"


func get_tooltip_text() -> String:
	# This text appears when the mouse hovers over the tile.
	var lines := [
		"Tile %02d" % tile_index,
		get_action_name()
	]

	if has_star_token and not star_collected:
		lines.append("Star token here")
	elif has_star_token:
		lines.append("Star collected")

	return "\n".join(lines)


func update_visuals() -> void:
	if not is_node_ready():
		return

	# Keep the icon, star and label matching the current Inspector values.
	# The tile background itself is repainted by _draw via queue_redraw().
	icon_sprite.texture = ICON_TEXTURES.get(tile_type)
	icon_sprite.visible = icon_sprite.texture != null
	star_sprite.texture = STAR_TEXTURE
	star_sprite.visible = has_star_token and not star_collected

	# %02d pads the tile number to two digits (5 becomes "05"),
	# and \n starts a new line inside the label.
	label.text = "%02d\n%s" % [tile_index, _short_action_label()]
	queue_redraw()


func _short_action_label() -> String:
	match tile_type:
		TileType.MOVE_FORWARD:
			return "+%d" % move_forward_amount
		TileType.JUMP:
			return "J%d" % jump_target_index
		TileType.SWAP_PLAYERS:
			return "SWAP"
		TileType.GAIN_LIFE:
			return "+LIFE"
		TileType.HAZARD:
			return "OUCH"
	return ""
