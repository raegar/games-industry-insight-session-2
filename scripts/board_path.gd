extends Node2D

# BoardPath draws a glowing track that links every board square in order.
# It sits behind the tiles so the squares look like stops along a route.
# It reads the tiles from the sibling "Board" node, so you never have to update
# this by hand when you move squares around.

const TRACK_COLOR := Color(0.55, 0.75, 1.0)

# The centre point of every tile, in travel order. A PackedVector2Array is
# just a fast list of 2D points - exactly what the line-drawing functions want.
var points: PackedVector2Array = PackedVector2Array()

func _ready() -> void:
	_gather_points()
	queue_redraw()


func _gather_points() -> void:
	# Collect the centre of every tile, in board order, to use as track points.
	points = PackedVector2Array()
	var board := get_parent().get_node_or_null("Board")
	if board == null:
		return

	var tiles: Array = []
	for child in board.get_children():
		if child is BoardPosition:
			tiles.append(child)

	tiles.sort_custom(func(a: BoardPosition, b: BoardPosition) -> bool:
		return a.tile_index < b.tile_index
	)

	for tile in tiles:
		points.append(tile.position)


func _draw() -> void:
	if points.size() < 2:
		return

	# The board winds back and forth in rows rather than forming a circle, so we
	# draw an open path that follows the tile order. (We deliberately don't join
	# the last tile back to the first, which would cut a line across the board.)
	# Several lines of decreasing width stacked on top of each other create a
	# soft outer glow with a bright core, like a neon strip.
	draw_polyline(points, Color(TRACK_COLOR, 0.10), 28.0, true)
	draw_polyline(points, Color(TRACK_COLOR, 0.18), 16.0, true)
	draw_polyline(points, Color(0.80, 0.90, 1.0, 0.50), 5.0, true)

	# A small glowing pip marks the centre of each square.
	for point in points:
		draw_circle(point, 6.0, Color(0.85, 0.95, 1.0, 0.55))
