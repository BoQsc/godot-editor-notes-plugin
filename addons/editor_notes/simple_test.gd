@tool
extends Control

var font_size = 16
var base_font: Font

func _ready():
	base_font = ThemeDB.fallback_font
	queue_redraw()

func _draw():
	# White background
	draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)
	
	# Test text
	var test_text = "Hello World! This is a test."
	var pos = Vector2(10, 30)
	
	# Draw text
	base_font.draw_string(get_canvas_item(), pos, test_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)
	
	# Draw cursor at end of text
	var text_width = base_font.get_string_size(test_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var cursor_pos = pos + Vector2(text_width, 0)
	draw_line(cursor_pos, cursor_pos + Vector2(0, 20), Color.RED, 2)
	
	# Test alignment
	draw_rect(Rect2(cursor_pos.x - 1, cursor_pos.y - 2, 2, 24), Color.BLUE)