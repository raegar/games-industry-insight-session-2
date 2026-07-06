extends Node2D

# GameManager is the main rules script.
# It controls turns, dice rolls, movement, tile effects, winning, and UI updates.
#
# "const" means a value that never changes while the game runs. Gathering them
# here makes the game easy to tune - all the _TIME values are in seconds.
const WINNING_STAR_COUNT := 3  # Stars needed to win.
const STEP_GLIDE_TIME := 0.35  # How long one step of movement takes.
const SPECIAL_GLIDE_TIME := 0.45  # Slower glide used for portals and player swaps.
const TILE_FEEDBACK_TIME := 0.8  # Pause so players can read what a tile did.
const TOOLTIP_OFFSET := Vector2(18, 18)  # Tooltip sits down-and-right of the mouse.
const PLAYER_TILE_OFFSETS := [
	# The two players stand slightly apart when they share the same tile.
	Vector2(-20, -10),
	Vector2(20, -10)
]

# These @onready variables point to nodes in Main.tscn.
# They let this script update labels, buttons, players, and the board.
@onready var board: Node2D = $Board
@onready var players_root: Node2D = $Players
@onready var turn_label: Label = $UI/TurnLabel
@onready var dice_label: Label = $UI/DiceLabel
@onready var status_label: Label = $UI/StatusLabel
@onready var player_one_label: Label = $UI/PlayerOneLabel
@onready var player_two_label: Label = $UI/PlayerTwoLabel
@onready var roll_button: Button = $UI/RollButton
@onready var skip_swap_button: Button = $UI/SkipSwapButton
@onready var reset_button: Button = $UI/ResetButton
@onready var tile_tooltip_panel: PanelContainer = $UI/TileTooltipPanel
@onready var tile_tooltip_label: Label = $UI/TileTooltipPanel/TileTooltipLabel
# STUDENT EXTENSION SPACE: adding sound effects to tiles?
# Add your new AudioStreamPlayer variables right below star_sound.
@onready var star_sound: AudioStreamPlayer = $StarSound

# These variables track the state of the game while it runs.
var board_positions: Array[BoardPosition] = []  # Every tile, sorted into board order.
var players: Array[PlayerToken] = []  # The two player tokens.
var current_player_index := 0  # 0 means Player 1's turn, 1 means Player 2's.
var swap_used_this_turn := false
var roll_started_this_turn := false
var game_over := false
var selected_swap_positions: Array[BoardPosition] = []  # Tiles clicked for a swap (max 2).
var hovered_board_position: BoardPosition = null  # The tile under the mouse, if any.
var rng := RandomNumberGenerator.new()  # Our dice.

func _ready() -> void:
	# _ready runs once, when this node first appears in the game.
	# randomize() seeds the dice so every game gets different rolls.
	rng.randomize()
	# .connect() wires a signal to a function: "when this button is pressed,
	# run that function". This is how Godot links the UI to the code.
	roll_button.pressed.connect(roll_dice)
	skip_swap_button.pressed.connect(skip_square_swap)
	reset_button.pressed.connect(start_game)
	start_game()


func _process(_delta: float) -> void:
	# Keep the tile tooltip following the mouse while it is visible.
	if tile_tooltip_panel.visible:
		if hovered_board_position != null:
			tile_tooltip_label.text = hovered_board_position.get_tooltip_text()
		_update_tile_tooltip_position()


func start_game() -> void:
	# Find every editable BoardPosition node in the scene.
	board_positions.clear()
	for child in board.get_children():
		# "is" checks a node's type, so anything that is not a tile gets skipped.
		if child is BoardPosition:
			board_positions.append(child)
			# Reset can run many times, so only connect signals that are not
			# already connected (connecting twice would cause double events).
			if not child.selected.is_connected(select_square_for_swap):
				child.selected.connect(select_square_for_swap)
			if not child.hovered.is_connected(_show_tile_tooltip):
				child.hovered.connect(_show_tile_tooltip)
			if not child.hover_ended.is_connected(_hide_tile_tooltip):
				child.hover_ended.connect(_hide_tile_tooltip)
			child.star_collected = false
			child.set_swap_selected(false)

	# Sort by tile_index so movement follows the board order, not scene order.
	# sort_custom takes a mini-function (a "lambda") that answers one question:
	# should tile a come before tile b? Here: yes, if its number is smaller.
	board_positions.sort_custom(func(a: BoardPosition, b: BoardPosition) -> bool:
		return a.tile_index < b.tile_index
	)

	players.clear()
	for child in players_root.get_children():
		if child is PlayerToken:
			players.append(child)

	# Player 1 starts on tile 0; Player 2 starts half-way round on tile 18.
	players[0].reset_for_new_game(0)
	players[1].reset_for_new_game(18)
	current_player_index = 0
	game_over = false
	dice_label.text = "Dice: -"
	_update_player_positions()
	begin_turn()


func begin_turn() -> void:
	# Each turn starts with the option to swap two squares before rolling.
	swap_used_this_turn = false
	roll_started_this_turn = false
	_clear_swap_selection()
	roll_button.disabled = false
	skip_swap_button.disabled = false
	status_label.text = "%s can swap two squares, or roll now." % _current_player().player_name
	_update_ui()


# STUDENT EXTENSION SPACE: showing more game info on screen?
# Add your new label updates at the bottom of this function.
func _update_ui() -> void:
	var current_player := _current_player()
	turn_label.text = "Turn: %s" % current_player.player_name
	player_one_label.text = _player_summary(players[0])
	player_two_label.text = _player_summary(players[1])


func _player_summary(player: PlayerToken) -> String:
	# %s and %d are placeholders: each gets filled in, in order, by the values
	# in the list after the % sign (%s = text, %d = whole number).
	return "%s  Stars: %d/%d  Lives: %d  Tile: %d" % [
		player.player_name,
		player.stars_collected,
		WINNING_STAR_COUNT,
		player.lives,
		player.tile_index
	]


func select_square_for_swap(board_position: BoardPosition) -> void:
	# The player may only swap before rolling, and only once per turn.
	if game_over or roll_started_this_turn or swap_used_this_turn:
		return

	# Clicking a square that is already selected un-selects it again.
	if selected_swap_positions.has(board_position):
		selected_swap_positions.erase(board_position)
		board_position.set_swap_selected(false)
		status_label.text = "Pick two different squares to swap, or roll now."
		return

	selected_swap_positions.append(board_position)
	board_position.set_swap_selected(true)

	# As soon as two different squares are selected, swap their effects.
	if selected_swap_positions.size() == 1:
		status_label.text = "Selected tile %d. Pick one more square." % board_position.tile_index
	elif selected_swap_positions.size() == 2:
		swap_selected_squares()


func _show_tile_tooltip(board_position: BoardPosition) -> void:
	# A tile emitted its "hovered" signal - the mouse just moved onto it.
	hovered_board_position = board_position
	tile_tooltip_label.text = board_position.get_tooltip_text()
	tile_tooltip_panel.visible = true
	_update_tile_tooltip_position()


func _hide_tile_tooltip(board_position: BoardPosition) -> void:
	# Only hide the tooltip if the mouse left the tile we are showing info for.
	# (Moving quickly between tiles can deliver events out of order.)
	if hovered_board_position != board_position:
		return

	hovered_board_position = null
	tile_tooltip_panel.visible = false


func _update_tile_tooltip_position() -> void:
	# Put the tooltip near the mouse, but keep it inside the game window.
	var viewport_size := get_viewport_rect().size
	var wanted_position := get_viewport().get_mouse_position() + TOOLTIP_OFFSET
	var tooltip_size := tile_tooltip_panel.size
	tile_tooltip_panel.position = Vector2(
		min(wanted_position.x, viewport_size.x - tooltip_size.x - 8.0),
		min(wanted_position.y, viewport_size.y - tooltip_size.y - 8.0)
	)


func swap_selected_squares() -> void:
	if selected_swap_positions.size() != 2:
		return

	# This swaps tile effects, not physical board positions or star tokens.
	var first := selected_swap_positions[0]
	var second := selected_swap_positions[1]
	var first_data := first.get_swappable_data()
	var second_data := second.get_swappable_data()
	first.apply_swappable_data(second_data)
	second.apply_swappable_data(first_data)

	swap_used_this_turn = true
	skip_swap_button.disabled = true
	status_label.text = "%s swapped tiles %d and %d. Now roll!" % [
		_current_player().player_name,
		first.tile_index,
		second.tile_index
	]
	_clear_swap_selection()


func skip_square_swap() -> void:
	# Skipping still uses up the swap choice for this turn.
	if game_over or roll_started_this_turn:
		return

	swap_used_this_turn = true
	skip_swap_button.disabled = true
	_clear_swap_selection()
	status_label.text = "%s skipped the square swap. Time to roll!" % _current_player().player_name


func roll_dice() -> void:
	# Once rolling starts, the player can no longer swap squares this turn.
	if game_over or roll_started_this_turn:
		return

	roll_started_this_turn = true
	roll_button.disabled = true
	skip_swap_button.disabled = true
	_clear_swap_selection()

	var roll := rng.randi_range(1, 6)  # A random whole number from 1 to 6.
	dice_label.text = "Dice: %d" % roll
	status_label.text = "%s rolled %d." % [_current_player().player_name, roll]
	# "await" pauses THIS function until the movement finishes, without
	# freezing the game - animations keep playing and the screen keeps drawing.
	await move_current_player(roll)
	await resolve_landed_tile(_tile_at(_current_player().tile_index))
	if check_for_knockout():
		return
	if not check_for_winner():
		# A neat maths trick to take turns: 1 - 0 = 1 and 1 - 1 = 0,
		# so this line flips between Player 1 and Player 2.
		current_player_index = 1 - current_player_index
		begin_turn()


func move_current_player(steps: int) -> void:
	# Move one tile at a time so the glide animation is easy to follow.
	for _step in range(steps):
		var player := _current_player()
		# % gives the remainder after dividing, which wraps the board around:
		# on a 36-tile board, tile 35 + 1 becomes 36 % 36 = 0. Back to the start!
		player.tile_index = (player.tile_index + 1) % board_positions.size()
		await _glide_player_to_current_tile(player, current_player_index, STEP_GLIDE_TIME)


func resolve_landed_tile(tile: BoardPosition, chain_depth: int = 0) -> void:
	# This is the main "what happens when you land here?" function.
	# chain_depth counts how many boosts/portals have fired in a row, so two
	# portals pointing at each other cannot bounce a player back and forth forever.
	var player := _current_player()

	if collect_star_if_present(tile):
		status_label.text = "%s collected a star!" % player.player_name
		_update_ui()
		await get_tree().create_timer(0.6).timeout

	# "match" compares one value against several options - like a tidier
	# version of a long if/elif chain. Exactly one branch runs.
	match tile.tile_type:
		BoardPosition.TileType.NORMAL:
			status_label.text = "%s found quiet space." % player.player_name
		BoardPosition.TileType.MOVE_FORWARD:
			# Boost tiles move the player again, then resolve whatever they land
			# on, so the new tile's effect (hazard, portal, star...) still counts.
			status_label.text = "%s hit a boost: move forward %d!" % [player.player_name, tile.move_forward_amount]
			await get_tree().create_timer(0.4).timeout
			await move_current_player(tile.move_forward_amount)
			var boosted_tile := _tile_at(player.tile_index)
			if chain_depth < 4:
				await resolve_landed_tile(boosted_tile, chain_depth + 1)
			else:
				status_label.text = "%s's boost chain fizzled out." % player.player_name
		BoardPosition.TileType.JUMP:
			# Portal tiles count as landing on the destination tile too.
			status_label.text = "%s used a portal to tile %d!" % [player.player_name, tile.jump_target_index]
			await get_tree().create_timer(0.4).timeout
			player.tile_index = _wrap_tile_index(tile.jump_target_index)
			await _glide_player_to_current_tile(player, current_player_index, SPECIAL_GLIDE_TIME)
			var destination_tile := _tile_at(player.tile_index)
			if chain_depth < 4:
				await resolve_landed_tile(destination_tile, chain_depth + 1)
			else:
				status_label.text = "%s's portal chain fizzled out." % player.player_name
		BoardPosition.TileType.SWAP_PLAYERS:
			status_label.text = "%s swapped places with the other player!" % player.player_name
			await _swap_player_positions()
		BoardPosition.TileType.GAIN_LIFE:
			player.lives += 1
			player.play_celebration()
			status_label.text = "%s gained a life." % player.player_name
		BoardPosition.TileType.HAZARD:
			# STUDENT EXTENSION SPACE: the Battle To Dodge Hazards worksheet starts here.
			# max(0, ...) stops lives going below zero.
			player.lives = max(0, player.lives - 1)
			status_label.text = "%s hit a hazard and lost a life." % player.player_name

	_update_player_positions()
	_update_ui()
	await get_tree().create_timer(TILE_FEEDBACK_TIME).timeout


func collect_star_if_present(tile: BoardPosition) -> bool:
	# BoardPosition.collect_star() handles hiding the star sprite.
	if tile.collect_star():
		var player := _current_player()
		player.stars_collected += 1
		player.play_celebration()
		star_sound.play()
		_update_ui()
		return true
	return false


func check_for_winner() -> bool:
	# The game ends as soon as the current player has enough stars.
	var player := _current_player()
	if player.stars_collected >= WINNING_STAR_COUNT:
		game_over = true
		roll_button.disabled = true
		skip_swap_button.disabled = true
		status_label.text = "%s wins! Press Reset Game to play again." % player.player_name
		_update_ui()
		return true
	return false


func check_for_knockout() -> bool:
	# The game also ends if a player runs out of lives - the other player wins.
	# 1 - index is the same flip trick used for taking turns.
	for index in range(players.size()):
		var player := players[index]
		if player.lives <= 0:
			var other_player := players[1 - index]
			game_over = true
			roll_button.disabled = true
			skip_swap_button.disabled = true
			status_label.text = "%s is out of lives! %s wins! Press Reset Game to play again." % [
				player.player_name,
				other_player.player_name
			]
			_update_ui()
			return true
	return false


func _swap_player_positions() -> void:
	# Swap player tile numbers, then animate both tokens to their new locations.
	var first_tile := players[0].tile_index
	players[0].tile_index = players[1].tile_index
	players[1].tile_index = first_tile
	players[0].set_moving(true)
	players[1].set_moving(true)
	var tween := create_tween()
	# set_parallel makes both position tweens play at the same time,
	# so the two tokens cross paths instead of moving one after the other.
	tween.set_parallel(true)
	tween.tween_property(players[0], "position", _player_target_position(0), SPECIAL_GLIDE_TIME)
	tween.tween_property(players[1], "position", _player_target_position(1), SPECIAL_GLIDE_TIME)
	await tween.finished
	players[0].set_moving(false)
	players[1].set_moving(false)


func _update_player_positions() -> void:
	# Snap every token straight onto its tile with no animation (used on reset).
	for index in range(players.size()):
		var player := players[index]
		player.position = _player_target_position(index)


func _glide_player_to_current_tile(player: PlayerToken, player_index: int, glide_time: float) -> void:
	# Tweens smoothly change a property over time. Here we tween the position.
	player.set_moving(true)
	var tween := create_tween()
	tween.tween_property(player, "position", _player_target_position(player_index), glide_time)
	await tween.finished
	player.set_moving(false)


func _player_target_position(player_index: int) -> Vector2:
	# Convert a player's tile_index into an actual screen position.
	var player := players[player_index]
	var tile := _tile_at(player.tile_index)
	return tile.position + PLAYER_TILE_OFFSETS[player_index]


func _tile_at(tile_index: int) -> BoardPosition:
	# Turn a tile number into the actual tile node, wrapping around the board.
	return board_positions[_wrap_tile_index(tile_index)]


func _wrap_tile_index(tile_index: int) -> int:
	# posmod is like % but never gives a negative answer, so even "tile -1"
	# safely wraps around to the last tile on the board.
	return posmod(tile_index, board_positions.size())


func _current_player() -> PlayerToken:
	# A small helper so the rest of the code reads like English.
	return players[current_player_index]


func _clear_swap_selection() -> void:
	# Un-highlight any tiles picked for a swap and forget about them.
	for board_position in selected_swap_positions:
		board_position.set_swap_selected(false)
	selected_swap_positions.clear()
