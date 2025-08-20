@tool
extends Control
class_name RichEditor

# Text formatting data structure
class TextSegment:
	var text: String
	var bold: bool = false
	var italic: bool = false
	var strikethrough: bool = false
	var code: bool = false
	var heading_level: int = 0  # 0 = not a heading, 1-6 = H1-H6
	
	func _init(txt: String = "", b: bool = false, i: bool = false, s: bool = false, c: bool = false, h: int = 0):
		text = txt
		bold = b
		italic = i
		strikethrough = s
		code = c
		heading_level = h
	
	func copy() -> TextSegment:
		return TextSegment.new(text, bold, italic, strikethrough, code, heading_level)

# Editor state
var segments: Array[TextSegment] = []
var cursor_position: int = 0
var selection_start: int = -1
var selection_end: int = -1
var current_format: TextSegment = TextSegment.new()

# Line number drag state
var line_drag_active: bool = false
var line_drag_start_line: int = -1

# Undo/Redo system
class UndoState:
	var segments_data: Array[TextSegment]
	var cursor_pos: int
	var selection_start_pos: int
	var selection_end_pos: int
	
	func _init(segs: Array[TextSegment], cursor: int, sel_start: int, sel_end: int):
		segments_data = []
		for seg in segs:
			segments_data.append(seg.copy())
		cursor_pos = cursor
		selection_start_pos = sel_start
		selection_end_pos = sel_end

var undo_stack: Array[UndoState] = []
var redo_stack: Array[UndoState] = []
var max_undo_steps: int = 100

# Fonts and styling
var base_font: Font
var bold_font: Font  
var italic_font: Font
var bold_italic_font: Font
var code_font: Font

# Visual properties
var font_size: int = 16
var line_height: float = 20.0
var line_number_width: float = 40.0  # Width of line number sidebar
var margin: Vector2 = Vector2(10, 2)
var text_margin: Vector2 = Vector2(50, 2)  # Text starts after line numbers
var cursor_blink_time: float = 0.0
var cursor_visible: bool = true

# Scrolling properties
var scroll_offset: float = 0.0
var total_content_height: float = 0.0
var scrollbar_width: float = 16.0
var scroll_dragging: bool = false
var scroll_drag_start_y: float = 0.0
var scroll_drag_start_offset: float = 0.0

# Performance caching
var cached_line_data: Array = []
var line_data_dirty: bool = true
var cached_content_height: float = 0.0

# Signals
signal text_changed()

# Context menu
var context_menu: Control
var context_menu_just_shown: bool = false

# Mouse tracking for drag detection
var mouse_down_position: Vector2
var drag_threshold: float = 3.0  # Minimum pixels to start selection
var intentional_empty_line_selection: bool = false  # Track if empty line was selected intentionally

func _ready():
	# Enable content clipping to prevent drawing outside bounds
	clip_contents = true
	
	# Set up focus and input handling
	set_focus_mode(Control.FOCUS_ALL)
	mouse_filter = Control.MOUSE_FILTER_STOP
	
	# Initialize fonts
	setup_fonts()
	
	# Set up initial text content
	setup_initial_text()
	
	# Set up context menu
	setup_context_menu()
	
	# Enable input handling
	set_process_input(true)
	set_process_unhandled_input(true)
	set_process(true)
	
	# Make sure we can receive focus
	focus_mode = Control.FOCUS_ALL
	
	# Connect focus signals to hide context menu when unfocused
	focus_exited.connect(_on_focus_exited)
	
	# Set mouse cursor to text edit cursor
	mouse_default_cursor_shape = Control.CURSOR_IBEAM
	
	# Auto-focus when ready
	call_deferred("grab_focus")

func setup_fonts():
	# Get the actual editor interface theme and code editor font
	var editor_interface = Engine.get_singleton("EditorInterface")
	var editor_theme = editor_interface.get_editor_theme() if editor_interface else null
	
	if editor_theme:
		# Try to get the code editor font
		base_font = editor_theme.get_font("source", "EditorFonts")
		if not base_font:
			# Fallback to main editor font
			base_font = editor_theme.get_font("main", "EditorFonts")
		if not base_font:
			# Final fallback
			base_font = ThemeDB.fallback_font
		
		# Get font size from editor settings
		font_size = editor_theme.get_font_size("source_size", "EditorFonts")
		if font_size <= 0:
			font_size = 16  # Fallback size
	else:
		base_font = ThemeDB.fallback_font
		font_size = 16
	
	# Create variations for different styles
	# Note: In a real implementation, you'd load actual bold/italic font files
	bold_font = base_font
	italic_font = base_font
	bold_italic_font = base_font
	code_font = base_font
	
	# Update line height based on font
	line_height = base_font.get_height(font_size) + 4

func setup_initial_text():
	# Start with a single empty segment
	segments = [TextSegment.new("")]
	cursor_position = 0

func setup_context_menu():
	# Prevent multiple context menu creation
	if context_menu != null:
		return
		
	# Create custom control that forwards events (non-modal)
	context_menu = Control.new()
	add_child(context_menu)
	context_menu.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	context_menu.size = Vector2(120, 120)
	context_menu.visible = false
	
	# Re-enable input handler for double-click forwarding
	context_menu.gui_input.connect(_on_context_menu_input)
	
	# Create background panel with PopupMenu styling
	var panel = Panel.new()
	context_menu.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Don't block button clicks
	
	# Style panel to match PopupMenu
	var editor_interface = Engine.get_singleton("EditorInterface")
	var editor_theme = editor_interface.get_editor_theme() if editor_interface else null
	var panel_bg = Color(0.2, 0.23, 0.31)  # Default dark theme
	
	if editor_theme:
		var theme_bg = editor_theme.get_color("panel_bg", "PopupMenu")
		if theme_bg != Color.BLACK:
			panel_bg = theme_bg
		else:
			theme_bg = editor_theme.get_color("bg", "Panel")
			if theme_bg != Color.BLACK:
				panel_bg = theme_bg
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = panel_bg
	panel_style.set_border_width_all(1)
	panel_style.border_color = panel_bg.darkened(0.2)
	panel_style.set_corner_radius_all(0)
	panel_style.shadow_size = 4
	panel_style.shadow_color = Color(0, 0, 0, 0.3)
	panel.add_theme_stylebox_override("panel", panel_style)
	
	# Create vertical container for menu items
	var vbox = VBoxContainer.new()
	context_menu.add_child(vbox)
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 0)
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS  # Allow clicks through to buttons
	
	# Add menu buttons
	create_menu_item(vbox, "Cut", func(): cut_selection(); context_menu.hide())
	create_menu_item(vbox, "Copy", func(): copy_selection(); context_menu.hide())
	create_menu_item(vbox, "Paste", func(): paste_from_clipboard(); context_menu.hide())
	
	# Add separator
	var separator = HSeparator.new()
	vbox.add_child(separator)
	
	create_menu_item(vbox, "Select All", func(): select_all(); context_menu.hide())

func create_menu_item(parent: VBoxContainer, text: String, callback: Callable):
	var btn = Button.new()
	btn.text = text
	btn.flat = false
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size.y = 24
	btn.mouse_filter = Control.MOUSE_FILTER_STOP  # Ensure button captures mouse events
	btn.focus_mode = Control.FOCUS_NONE  # Don't steal focus but allow clicks
	
	# Get actual PopupMenu colors from editor theme
	var editor_interface = Engine.get_singleton("EditorInterface")
	var editor_theme = editor_interface.get_editor_theme() if editor_interface else null
	
	var menu_bg_color: Color = Color(0.2, 0.23, 0.31)  # Default dark theme
	var menu_hover_color: Color = Color(0.26, 0.32, 0.46)  # Default hover
	var menu_font_color: Color = Color(0.875, 0.875, 0.875)  # Default text
	var menu_font_hover_color: Color = Color.WHITE  # Default hover text
	
	if editor_theme:
		# Try extracting actual PopupMenu colors
		var theme_bg = editor_theme.get_color("panel_bg", "PopupMenu")
		if theme_bg != Color.BLACK:
			menu_bg_color = theme_bg
		else:
			# Try Panel as fallback
			theme_bg = editor_theme.get_color("bg", "Panel")
			if theme_bg != Color.BLACK:
				menu_bg_color = theme_bg
		
		var theme_hover = editor_theme.get_color("hover", "PopupMenu")
		if theme_hover != Color.BLACK:
			menu_hover_color = theme_hover
		else:
			# Try Button hover as fallback
			theme_hover = editor_theme.get_color("hover", "Button")
			if theme_hover != Color.BLACK:
				menu_hover_color = theme_hover
		
		var theme_font = editor_theme.get_color("font_color", "PopupMenu")
		if theme_font != Color.BLACK:
			menu_font_color = theme_font
		else:
			# Try Label font color as fallback
			theme_font = editor_theme.get_color("font_color", "Label")
			if theme_font != Color.BLACK:
				menu_font_color = theme_font
	
	# Create button states with theme colors - ensure flat appearance like PopupMenu
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = menu_bg_color
	normal_style.set_border_width_all(0)
	normal_style.set_corner_radius_all(0)
	normal_style.content_margin_left = 8
	normal_style.content_margin_right = 8
	normal_style.content_margin_top = 4
	normal_style.content_margin_bottom = 4
	
	var hover_style = StyleBoxFlat.new()
	hover_style.bg_color = menu_hover_color
	hover_style.set_border_width_all(0)
	hover_style.set_corner_radius_all(0)
	hover_style.content_margin_left = 8
	hover_style.content_margin_right = 8
	hover_style.content_margin_top = 4
	hover_style.content_margin_bottom = 4
	
	# Apply states with proper PopupMenu styling
	btn.add_theme_stylebox_override("normal", normal_style)
	btn.add_theme_stylebox_override("hover", hover_style)
	btn.add_theme_stylebox_override("pressed", hover_style)
	btn.add_theme_stylebox_override("focus", normal_style)
	
	# Apply font colors
	btn.add_theme_color_override("font_color", menu_font_color)
	btn.add_theme_color_override("font_hover_color", menu_font_hover_color)
	btn.add_theme_color_override("font_pressed_color", menu_font_hover_color)
	
	btn.pressed.connect(callback)
	parent.add_child(btn)

func _on_focus_exited():
	# Hide context menu when editor loses focus
	if context_menu and context_menu.visible:
		context_menu.hide()
		context_menu_just_shown = false

func _on_context_menu_input(event):
	# With proper mouse filtering, this should only receive unhandled events
	# (events that didn't hit buttons, since buttons have MOUSE_FILTER_STOP)
	if event is InputEventMouseButton and event.pressed:
		# Calculate the position relative to the text editor
		var editor_pos = event.position + context_menu.position
		
		# Create new event with correct position
		var new_event = InputEventMouseButton.new()
		new_event.button_index = event.button_index
		new_event.pressed = event.pressed
		new_event.double_click = event.double_click
		new_event.position = editor_pos
		
		# Close context menu and process the event
		context_menu.hide()
		context_menu_just_shown = false
		handle_mouse_input(new_event)

func _draw():
	# Calculate total content height
	calculate_content_height()
	
	# Clamp scroll offset to valid range
	clamp_scroll_offset()
	
	# Debug: Ensure we have proper bounds
	if size.x <= 0 or size.y <= 0:
		return  # Don't draw if we don't have proper size
	
	# Note: Using clip_contents = true for automatic clipping
	
	draw_background()
	draw_line_numbers()
	draw_selection()  # Draw selection behind text
	draw_text_segments()
	draw_cursor()  # Draw cursor on top
	draw_scrollbar()  # Draw scrollbar on top

func draw_background():
	# Get the actual editor interface theme with error handling
	var editor_interface = null
	var editor_theme = null
	
	# Safe theme access
	if Engine.has_singleton("EditorInterface"):
		editor_interface = Engine.get_singleton("EditorInterface")
		if editor_interface and editor_interface.has_method("get_editor_theme"):
			editor_theme = editor_interface.get_editor_theme()
	
	var bg_color: Color
	var line_number_bg_color: Color
	if editor_theme:
		# Use the darker panel/input background color like console and scene tree
		bg_color = editor_theme.get_color("dark_color_2", "Editor")
		if bg_color == Color.BLACK:  # Try alternative darker color
			bg_color = editor_theme.get_color("dark_color_1", "Editor")
		if bg_color == Color.BLACK:  # Try LineEdit background
			bg_color = editor_theme.get_color("base_color", "LineEdit")
		if bg_color == Color.BLACK:  # Final fallback
			bg_color = Color(0.14, 0.17, 0.22)  # Darker editor panel color
		
		# Line number background should be slightly darker
		line_number_bg_color = bg_color.darkened(0.1)
	else:
		bg_color = Color(0.14, 0.17, 0.22)  # Fallback
		line_number_bg_color = Color(0.12, 0.15, 0.20)  # Darker fallback
	
	# Draw main text area background
	draw_rect(Rect2(Vector2(line_number_width, 0), Vector2(size.x - line_number_width, size.y)), bg_color)
	
	# Draw line number area background
	draw_rect(Rect2(Vector2.ZERO, Vector2(line_number_width, size.y)), line_number_bg_color)
	
	# Draw current line highlight
	draw_current_line_highlight(bg_color)
	
	# Draw separator line between line numbers and text
	var separator_color: Color
	if editor_theme:
		separator_color = editor_theme.get_color("font_color", "Editor")
		separator_color.a = 0.2
	else:
		separator_color = Color(0.4, 0.4, 0.4, 0.2)
	
	draw_line(Vector2(line_number_width, 0), Vector2(line_number_width, size.y), separator_color, 1.0)
	
	# Draw subtle border
	var border_color: Color
	if editor_theme:
		border_color = editor_theme.get_color("font_color", "Editor")
		border_color.a = 0.1  # Very subtle
	else:
		border_color = Color(0.35, 0.35, 0.35, 0.1)
	
	draw_rect(Rect2(Vector2.ZERO, size), border_color, false, 1.0)

func calculate_content_height():
	# Use cached height if available
	if cached_content_height > 0.0 and not line_data_dirty:
		total_content_height = cached_content_height
		return
	
	var line_data = get_line_data()
	total_content_height = text_margin.y
	for line_info in line_data:
		total_content_height += line_info.height
	
	# Cache the result
	cached_content_height = total_content_height

func draw_scrollbar():
	# Only draw scrollbar if content exceeds visible area
	if total_content_height <= size.y:
		return
	
	var scrollbar_x = size.x - scrollbar_width
	var scrollbar_track_rect = Rect2(Vector2(scrollbar_x, 0), Vector2(scrollbar_width, size.y))
	
	# Get editor theme colors
	var editor_interface = Engine.get_singleton("EditorInterface")
	var editor_theme = editor_interface.get_editor_theme() if editor_interface else null
	
	var track_color: Color = Color(0.1, 0.1, 0.1, 0.3)
	var thumb_color: Color = Color(0.4, 0.4, 0.4, 0.7)
	var thumb_hover_color: Color = Color(0.5, 0.5, 0.5, 0.8)
	
	if editor_theme:
		track_color = editor_theme.get_color("dark_color_1", "Editor")
		track_color.a = 0.3
		thumb_color = editor_theme.get_color("font_color", "Editor")
		thumb_color.a = 0.4
		thumb_hover_color = thumb_color
		thumb_hover_color.a = 0.6
	
	# Draw scrollbar track
	draw_rect(scrollbar_track_rect, track_color)
	
	# Calculate thumb size and position
	var visible_ratio = size.y / total_content_height
	var thumb_height = max(20.0, size.y * visible_ratio)
	var scroll_range = total_content_height - size.y
	var thumb_y = (scroll_offset / scroll_range) * (size.y - thumb_height) if scroll_range > 0 else 0
	
	# Draw scrollbar thumb
	var thumb_rect = Rect2(Vector2(scrollbar_x + 2, thumb_y), Vector2(scrollbar_width - 4, thumb_height))
	draw_rect(thumb_rect, thumb_color)

func draw_current_line_highlight(bg_color: Color):
	# Find which line the cursor is on using line data
	var line_data = get_line_data()
	var current_pos = 0
	var y_pos = text_margin.y - scroll_offset  # Apply scroll offset
	var target_line_height = line_height  # Default fallback
	var found_line = false
	
	for line_info in line_data:
		var line_segments = line_info.segments
		var line_height_val = line_info.height
		
		# Calculate line length
		var line_length = 0
		for segment_info in line_segments:
			line_length += segment_info.text.length()
		
		var line_end_pos = current_pos + line_length
		
		# Check if cursor is on this line
		if cursor_position >= current_pos and cursor_position <= line_end_pos:
			target_line_height = line_height_val
			found_line = true
			break
		
		y_pos += line_height_val
		current_pos = line_end_pos + 1  # +1 for newline
	
	# Create a subtle highlight color (lighter than background)
	var highlight_color = bg_color.lightened(0.03)  # Very subtle highlight
	highlight_color.a = 0.8
	
	# Draw highlight across entire line (both line number area and text area)
	var highlight_rect = Rect2(Vector2(0, y_pos), Vector2(size.x, target_line_height))
	draw_rect(highlight_rect, highlight_color)

func draw_line_numbers():
	# Get the actual editor interface theme
	var editor_interface = Engine.get_singleton("EditorInterface")
	var editor_theme = editor_interface.get_editor_theme() if editor_interface else null
	
	var line_number_color: Color
	if editor_theme:
		line_number_color = editor_theme.get_color("font_color", "Editor")
		line_number_color.a = 0.5  # Make line numbers more subtle
	else:
		line_number_color = Color(0.6, 0.6, 0.6, 0.5)
	
	# Draw line numbers using dynamic line heights
	var line_data = get_line_data()
	var line_number_font = base_font
	var y_pos = text_margin.y - scroll_offset  # Apply scroll offset
	
	# Viewport culling for line numbers
	var visible_start_y = 0
	var visible_end_y = size.y
	
	for line_idx in range(line_data.size()):
		var line_info = line_data[line_idx]
		var line_height_val = line_info.height
		
		# Viewport culling - skip line numbers outside visible area
		if y_pos + line_height_val < visible_start_y:
			y_pos += line_height_val
			continue
		if y_pos > visible_end_y:
			break
		
		var line_num = line_idx + 1
		var line_text = str(line_num)
		var text_width = line_number_font.get_string_size(line_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var x_pos = line_number_width - text_width - 5  # Right-align with 5px margin
		
		# Center the line number vertically within the line height
		var text_y = y_pos + line_number_font.get_ascent(font_size) + (line_height_val - line_number_font.get_height(font_size)) / 2
		
		line_number_font.draw_string(get_canvas_item(), Vector2(x_pos, text_y), line_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, line_number_color)
		
		y_pos += line_height_val
	
	# Handle case where there's no text - show line number 1
	if line_data.is_empty():
		var line_text = "1"
		var text_width = line_number_font.get_string_size(line_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var x_pos = line_number_width - text_width - 5
		var text_y = text_margin.y + line_number_font.get_ascent(font_size)
		line_number_font.draw_string(get_canvas_item(), Vector2(x_pos, text_y), line_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, line_number_color)

func draw_text_segments():
	# NEW APPROACH: Build line data first, then render line by line with dynamic heights
	var line_data = get_line_data()
	
	# Safety check for empty content
	if line_data.is_empty():
		return
	
	var pos = text_margin
	pos.y -= scroll_offset  # Apply scroll offset
	
	# Viewport culling - only draw visible lines
	var visible_start_y = 0
	var visible_end_y = size.y
	
	for line_info in line_data:
		var line_segments = line_info.segments
		var current_line_height = line_info.height
		
		# Viewport culling - skip lines outside visible area
		if pos.y + current_line_height < visible_start_y:
			pos.y += current_line_height
			continue
		if pos.y > visible_end_y:
			break
		
		# Draw each segment on this line
		var line_x = pos.x
		for segment_info in line_segments:
			var segment = segment_info.segment
			var text = segment_info.text
			var font = get_segment_font(segment)
			var segment_font_size = get_segment_font_size(segment)
			var color = get_segment_color(segment)
			
			if text.length() > 0:
				var line_width = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, segment_font_size).x
				var text_pos = Vector2(line_x, pos.y + font.get_ascent(segment_font_size))
				
				# Draw background for code segments
				if segment.code:
					var code_bg_color = color.lerp(Color.BLACK, 0.3)
					code_bg_color.a = 0.2
					draw_rect(Rect2(Vector2(line_x - 2, pos.y), Vector2(line_width + 4, current_line_height)), code_bg_color)
				
				# Draw the text with styling effects
				if segment.bold and not segment.code:
					# Simple bold effect
					var bold_color = color.lerp(Color.WHITE, 0.1)
					font.draw_string(get_canvas_item(), text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, segment_font_size, bold_color)
					font.draw_string(get_canvas_item(), text_pos + Vector2(0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, segment_font_size, bold_color)
					if segment.italic:
						font.draw_string(get_canvas_item(), text_pos + Vector2(1, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, segment_font_size, bold_color)
				elif segment.italic and not segment.code:
					# Simple italic effect with color change
					var italic_color = color.lerp(Color(1.0, 0.8, 0.6), 0.3)  
					font.draw_string(get_canvas_item(), text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, segment_font_size, italic_color)
				else:
					font.draw_string(get_canvas_item(), text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, segment_font_size, color)
				
				# Draw strikethrough if needed
				if segment.strikethrough and not segment.code:
					var strikethrough_y = text_pos.y - font.get_ascent(segment_font_size) / 2
					draw_line(Vector2(line_x, strikethrough_y), Vector2(line_x + line_width, strikethrough_y), color, 1.0)
				
				line_x += line_width
		
		# Move to next line using dynamic height
		pos.x = text_margin.x
		pos.y += current_line_height

func get_line_data() -> Array:
	# Return cached line data if available and not dirty
	if not line_data_dirty and cached_line_data.size() > 0:
		return cached_line_data
	
	# Rebuild line data
	cached_line_data = build_line_data_internal()
	line_data_dirty = false
	return cached_line_data

func build_line_data_internal() -> Array:
	# Build an array of line information with dynamic heights
	var line_data = []
	var current_pos = 0
	var current_line_segments = []
	var current_line_start = 0
	
	for segment in segments:
		var segment_lines = segment.text.split('\n')
		
		for line_idx in range(segment_lines.size()):
			var line_text = segment_lines[line_idx]
			
			# Add this line part to current line (including empty lines)
			current_line_segments.append({
				"segment": segment,
				"text": line_text
			})
			
			# If this is the end of a line (newline or last line of segment)
			if line_idx < segment_lines.size() - 1:
				# End of line - calculate height and add to line_data
				var line_segments_only = []
				for seg_info in current_line_segments:
					line_segments_only.append(seg_info.segment)
				
				var current_line_height = get_line_height_for_segments(line_segments_only)
				
				line_data.append({
					"segments": current_line_segments,
					"height": current_line_height,
					"start_pos": current_line_start
				})
				
				# Reset for next line
				current_line_segments = []
				current_pos += line_text.length() + 1  # +1 for newline
				current_line_start = current_pos
			else:
				current_pos += line_text.length()
	
	# Don't forget the last line (even if it's empty)
	if current_line_segments.size() > 0:
		var line_segments_only = []
		for seg_info in current_line_segments:
			line_segments_only.append(seg_info.segment)
		
		var current_line_height = get_line_height_for_segments(line_segments_only)
		
		line_data.append({
			"segments": current_line_segments,
			"height": current_line_height,
			"start_pos": current_line_start
		})
	
	# Ensure we always have at least one line (for empty editor)
	if line_data.is_empty():
		line_data.append({
			"segments": [],
			"height": line_height,  # Use default line height
			"start_pos": 0
		})
	
	return line_data

# Legacy function for compatibility - will be replaced gradually
func build_line_data() -> Array:
	return get_line_data()

func invalidate_cache():
	# Mark cache as dirty when content changes
	line_data_dirty = true
	cached_content_height = 0.0

func invalidate_cache_if_needed(old_length: int, new_length: int):
	# Smarter cache invalidation - only invalidate if content structure might have changed
	if old_length != new_length or (old_length > 0 and new_length > 0):
		# Content size changed or non-empty content modified
		invalidate_cache()

func cleanup_segments():
	# Remove empty segments and merge adjacent segments with identical formatting
	var cleaned_segments: Array[TextSegment] = []
	
	for segment in segments:
		if segment.text.length() == 0:
			continue  # Skip empty segments
		
		# Check if we can merge with the previous segment
		if cleaned_segments.size() > 0:
			var prev_segment = cleaned_segments[-1]
			if segments_have_same_formatting(prev_segment, segment):
				# Merge with previous segment
				prev_segment.text += segment.text
				continue
		
		# Add as new segment
		cleaned_segments.append(segment)
	
	# Ensure we have at least one segment
	if cleaned_segments.is_empty():
		cleaned_segments.append(TextSegment.new(""))
	
	segments = cleaned_segments

func segments_have_same_formatting(seg1: TextSegment, seg2: TextSegment) -> bool:
	return (seg1.bold == seg2.bold and 
			seg1.italic == seg2.italic and 
					seg1.strikethrough == seg2.strikethrough and 
			seg1.code == seg2.code and 
			seg1.heading_level == seg2.heading_level)

func get_segment_font(segment: TextSegment) -> Font:
	var font: Font
	
	if segment.code:
		font = code_font
	elif segment.bold and segment.italic:
		font = bold_italic_font
	elif segment.bold:
		font = bold_font
	elif segment.italic:
		font = italic_font
	else:
		font = base_font
	
	# Fallback to base font if selected font is null
	if font == null:
		font = base_font
		if font == null:
			# Emergency fallback - create a default font
			font = SystemFont.new()
	
	return font

func get_segment_font_size(segment: TextSegment) -> int:
	if segment.heading_level > 0:
		# Scale font size based on heading level
		var scale_factors = [2.0, 1.5, 1.25, 1.1, 1.0, 0.9]  # H1-H6
		var scale = scale_factors[segment.heading_level - 1]
		return int(font_size * scale)
	else:
		return font_size

func get_line_height_for_segments(segments_on_line: Array) -> float:
	# Calculate the maximum line height needed for all segments on a line
	var max_height = line_height  # Start with base line height
	
	for segment in segments_on_line:
		var font = get_segment_font(segment)
		var segment_font_size = get_segment_font_size(segment)
		var segment_height = font.get_height(segment_font_size) + 4  # Add some padding
		max_height = max(max_height, segment_height)
	
	return max_height

func get_line_height_at_position(text_pos: int) -> float:
	# Get the line height for the line containing the given position
	text_pos = clamp(text_pos, 0, get_total_text_length())
	
	var line_data = get_line_data()
	var current_pos = 0
	
	for line_info in line_data:
		var line_segments = line_info.segments
		var line_height_val = line_info.height
		
		# Calculate total length of this line
		var line_length = 0
		for segment_info in line_segments:
			line_length += segment_info.text.length()
		
		var line_end_pos = current_pos + line_length
		
		# Check if target position is on this line
		if text_pos <= line_end_pos:
			return line_height_val
		
		current_pos = line_end_pos + 1  # +1 for newline character
	
	# Fallback to default line height
	return line_height

func get_line_start_at_y(y_pos: float) -> int:
	# Find the start position of the line at the given Y coordinate
	var line_data = get_line_data()
	var current_y = text_margin.y - scroll_offset  # Apply scroll offset
	var current_pos = 0
	
	for line_info in line_data:
		var line_height_val = line_info.height
		
		# Check if Y position is within this line
		if y_pos >= current_y and y_pos < current_y + line_height_val:
			return current_pos
		
		# Calculate total length of this line
		var line_length = 0
		for segment_info in line_info.segments:
			line_length += segment_info.text.length()
		
		current_y += line_height_val
		current_pos += line_length + 1  # +1 for newline
	
	# If Y is beyond all lines, return end of text
	return get_total_text_length()

func get_line_end_at_y(y_pos: float) -> int:
	# Find the end position of the line at the given Y coordinate
	var line_data = get_line_data()
	var current_y = text_margin.y - scroll_offset  # Apply scroll offset
	var current_pos = 0
	
	for line_info in line_data:
		var line_height_val = line_info.height
		
		# Calculate total length of this line
		var line_length = 0
		for segment_info in line_info.segments:
			line_length += segment_info.text.length()
		
		# Check if Y position is within this line
		if y_pos >= current_y and y_pos < current_y + line_height_val:
			return current_pos + line_length
		
		current_y += line_height_val
		current_pos += line_length + 1  # +1 for newline
	
	# If Y is beyond all lines, return end of text
	return get_total_text_length()

func calculate_line_segments(line_start_pos: int, line_end_pos: int) -> Array:
	# Get all segments that affect a specific line
	var line_segments: Array = []
	var current_pos = 0
	
	for segment in segments:
		var segment_start = current_pos
		var segment_end = current_pos + segment.text.length()
		
		# Check if this segment overlaps with the line
		if segment_end > line_start_pos and segment_start < line_end_pos:
			line_segments.append(segment)
		
		current_pos += segment.text.length()
	
	return line_segments

func get_segment_color(segment: TextSegment) -> Color:
	# Get the actual editor theme
	var editor_interface = Engine.get_singleton("EditorInterface")
	var editor_theme = editor_interface.get_editor_theme() if editor_interface else null
	
	if segment.code:
		# Use a themed color for code text
		var code_color: Color
		if editor_theme:
			code_color = editor_theme.get_color("font_color", "Editor")
			code_color = code_color.lerp(Color.GREEN, 0.3)  # Tint towards green
		else:
			code_color = Color.LIGHT_GREEN  # Fallback
		return code_color
	else:
		# Use editor theme font color
		var text_color: Color
		if editor_theme:
			text_color = editor_theme.get_color("font_color", "Editor")
		else:
			text_color = Color(0.9, 0.9, 0.9)  # Fallback
		return text_color

func draw_cursor():
	if not cursor_visible:
		return
		
	var cursor_pos = get_visual_position(cursor_position)
	
	# Get cursor color from editor theme
	var editor_interface = Engine.get_singleton("EditorInterface")
	var editor_theme = editor_interface.get_editor_theme() if editor_interface else null
	var cursor_color: Color
	if editor_theme:
		cursor_color = editor_theme.get_color("font_color", "Editor")
	else:
		cursor_color = Color.WHITE  # Fallback
	
	# Get the actual line height for the cursor position
	var actual_line_height = get_line_height_at_position(cursor_position)
	
	# Make cursor smaller - reduced height and thickness based on actual line height
	var cursor_height = actual_line_height * 0.8  # 80% of actual line height
	var cursor_offset = actual_line_height * 0.1  # Small offset from top
	draw_line(cursor_pos + Vector2(0, cursor_offset), cursor_pos + Vector2(0, cursor_offset + cursor_height), cursor_color, 1.0)

func draw_selection():
	if selection_start == -1 or selection_end == -1:
		return
		
	var start_pos = min(selection_start, selection_end)
	var end_pos = max(selection_start, selection_end)
	
	# Handle zero-width selections (empty lines) specially - only for intentional selections
	if start_pos == end_pos:
		if intentional_empty_line_selection:
			draw_empty_line_selection(start_pos)
		# For zero-width drag selections, don't draw anything
		return
		
	# Use the multi-line drawing for actual selections
	draw_multi_line_selection(start_pos, end_pos)

func draw_empty_line_selection(pos: int):
	# Draw selection for empty line (zero-width selection)
	var visual_pos = get_visual_position(pos)
	var actual_line_height = get_line_height_at_position(pos)
	var space_width = base_font.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var selection_color = Color(0.3, 0.6, 1.0, 0.3)
	draw_rect(Rect2(visual_pos, Vector2(space_width, actual_line_height)), selection_color)

func draw_multi_line_selection(start_pos: int, end_pos: int):
	var selection_color = Color(0.3, 0.6, 1.0, 0.3)
	var space_width = base_font.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	
	# Use the same line-based approach as text rendering for consistency
	var line_data = get_line_data()
	var pos = text_margin
	pos.y -= scroll_offset  # Apply scroll offset
	var current_pos = 0
	
	# Viewport culling for selection drawing
	var visible_start_y = 0
	var visible_end_y = size.y
	
	for line_info in line_data:
		var line_segments = line_info.segments
		var line_height_val = line_info.height
		var line_start_pos = current_pos
		
		# Viewport culling - skip lines outside visible area
		if pos.y + line_height_val < visible_start_y:
			pos.y += line_height_val
			var line_length = 0
			for segment_info in line_segments:
				line_length += segment_info.text.length()
			current_pos += line_length + 1  # +1 for newline
			continue
		if pos.y > visible_end_y:
			break
		
		# Calculate total length of this line
		var line_length = 0
		for segment_info in line_segments:
			line_length += segment_info.text.length()
		
		var line_end_pos = line_start_pos + line_length
		
		# Check if this line intersects with the selection
		if line_end_pos >= start_pos and line_start_pos < end_pos:
			# Calculate selection boundaries within this line
			var sel_start_in_line = max(0, start_pos - line_start_pos)
			var sel_end_in_line = min(line_length, end_pos - line_start_pos)
			
			# Handle empty lines specially - they should show space-width selection
			if line_length == 0 and sel_start_in_line == 0:
				# Empty line - draw space-width selection
				var selection_rect = Rect2(
					Vector2(pos.x, pos.y), 
					Vector2(space_width, line_height_val)
				)
				draw_rect(selection_rect, selection_color)
			elif sel_start_in_line < sel_end_in_line:
				# Non-empty line with selection
				var line_x = pos.x
				var chars_processed = 0
				
				# Find the visual position where selection starts
				for segment_info in line_segments:
					var segment = segment_info.segment
					var text = segment_info.text
					var font = get_segment_font(segment)
					var segment_font_size = get_segment_font_size(segment)
					
					var segment_start = chars_processed
					var segment_end = chars_processed + text.length()
					
					# Check if selection intersects this segment
					if segment_end > sel_start_in_line and segment_start < sel_end_in_line:
						var sel_start_in_segment = max(0, sel_start_in_line - segment_start)
						var sel_end_in_segment = min(text.length(), sel_end_in_line - segment_start)
						
						if sel_start_in_segment < sel_end_in_segment:
							# Calculate positions for selection rectangle
							var prefix_text = text.substr(0, sel_start_in_segment) if sel_start_in_segment > 0 else ""
							var selected_text = text.substr(sel_start_in_segment, sel_end_in_segment - sel_start_in_segment)
							
							var prefix_width = 0.0
							if prefix_text.length() > 0:
								prefix_width = font.get_string_size(prefix_text, HORIZONTAL_ALIGNMENT_LEFT, -1, segment_font_size).x
							
							var selected_width = space_width  # Default for empty text
							if selected_text.length() > 0:
								selected_width = font.get_string_size(selected_text, HORIZONTAL_ALIGNMENT_LEFT, -1, segment_font_size).x
							
							var selection_rect = Rect2(
								Vector2(line_x + prefix_width, pos.y), 
								Vector2(selected_width, line_height_val)
							)
							draw_rect(selection_rect, selection_color)
					
					# Advance line_x position
					if text.length() > 0:
						var segment_width = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, segment_font_size).x
						line_x += segment_width
					
					chars_processed += text.length()
		
		# Move to next line position
		pos.x = text_margin.x
		pos.y += line_height_val
		current_pos = line_end_pos + 1  # +1 for newline character

func advance_draw_pos_for_segment(pos: Vector2, segment: TextSegment) -> Vector2:
	var font = get_segment_font(segment)
	var segment_font_size = get_segment_font_size(segment)
	var segment_lines = segment.text.split('\n')
	
	for line_idx in range(segment_lines.size()):
		var line = segment_lines[line_idx]
		if line_idx < segment_lines.size() - 1:
			# Move to next line
			pos.x = text_margin.x
			pos.y += line_height
		else:
			# Update x position
			pos.x += font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, segment_font_size).x
	
	return pos

func get_visual_position(text_pos: int) -> Vector2:
	# OPTIMIZED: Use pre-built line data with dynamic heights
	text_pos = clamp(text_pos, 0, get_total_text_length())
	
	var line_data = get_line_data()
	var pos = text_margin
	pos.y -= scroll_offset  # Apply scroll offset
	var current_pos = 0
	
	for line_info in line_data:
		var line_segments = line_info.segments
		var line_height_val = line_info.height
		var line_start_pos = current_pos
		
		# Calculate total length of this line
		var line_length = 0
		for segment_info in line_segments:
			line_length += segment_info.text.length()
		
		var line_end_pos = line_start_pos + line_length
		
		# Check if target position is on this line
		if text_pos <= line_start_pos:
			# Target is at start of this line
			return pos
		elif text_pos <= line_end_pos:
			# Target is within this line - calculate position
			var line_x = pos.x
			var chars_processed = 0
			
			for segment_info in line_segments:
				var segment = segment_info.segment
				var text = segment_info.text
				var font = get_segment_font(segment)
				var segment_font_size = get_segment_font_size(segment)
				
				var chars_into_segment = text_pos - line_start_pos - chars_processed
				
				if chars_into_segment <= 0:
					# Target is at the start of this segment
					return Vector2(line_x, pos.y)
				elif chars_into_segment >= text.length():
					# Target is beyond this segment - add full width
					var segment_width = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, segment_font_size).x
					line_x += segment_width
					chars_processed += text.length()
				else:
					# Target is within this segment
					var partial_text = text.substr(0, chars_into_segment)
					var partial_width = font.get_string_size(partial_text, HORIZONTAL_ALIGNMENT_LEFT, -1, segment_font_size).x
					line_x += partial_width
					return Vector2(line_x, pos.y)
			
			# If we get here, target is at end of line
			return Vector2(line_x, pos.y)
		
		# Move to next line
		pos.x = text_margin.x
		pos.y += line_height_val
		current_pos = line_end_pos + 1  # +1 for newline character (if exists)
	
	return pos

func _process(delta):
	# Handle cursor blinking - faster blink rate, only when focused
	if has_focus():
		cursor_blink_time += delta
		if cursor_blink_time >= 0.5:  # Changed from 1.0 to 0.5 for faster blinking
			cursor_visible = not cursor_visible
			cursor_blink_time = 0.0
			queue_redraw()
	else:
		# When not focused, hide cursor completely
		if cursor_visible != false:
			cursor_visible = false
			queue_redraw()

func _gui_input(event):
	if event is InputEventKey and event.pressed:
		handle_key_input(event)
		accept_event()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			scroll_up()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			scroll_down()
			accept_event()
		else:
			handle_mouse_input(event)
			accept_event()
	elif event is InputEventMouseMotion:
		handle_mouse_motion(event)
		accept_event()

func _unhandled_input(event):
	# Handle global mouse motion for selection even when outside bounds
	if event is InputEventMouseMotion and selection_start != -1 and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		# Convert global mouse position to local coordinates
		var local_pos = get_global_mouse_position() - global_position
		var drag_pos = get_text_position_at_extended(local_pos)
		selection_end = drag_pos
		cursor_position = drag_pos
		queue_redraw()
		get_viewport().set_input_as_handled()
		return
	
	if not has_focus():
		return
		
	if event is InputEventKey and event.pressed:
		handle_key_input(event)
		get_viewport().set_input_as_handled()

func handle_key_input(event: InputEventKey):
	var shift_pressed = event.shift_pressed
	var ctrl_pressed = event.ctrl_pressed
	
	match event.keycode:
		KEY_LEFT:
			if shift_pressed:
				start_selection()
			move_cursor(-1)
			if shift_pressed:
				update_selection()
			else:
				clear_selection()
		KEY_RIGHT:
			if shift_pressed:
				start_selection()
			move_cursor(1)
			if shift_pressed:
				update_selection()
			else:
				clear_selection()
		KEY_HOME:
			move_cursor_to_line_start()
		KEY_END:
			move_cursor_to_line_end()
		KEY_BACKSPACE:
			if has_selection():
				delete_selection()
			elif ctrl_pressed:
				delete_word(-1)
			else:
				delete_character(-1)
		KEY_DELETE:
			if has_selection():
				delete_selection()
			elif ctrl_pressed:
				delete_word(1)
			else:
				delete_character(1)
		KEY_ENTER:
			if has_selection():
				delete_selection()
			insert_character('\n')
		KEY_A:
			if ctrl_pressed:
				select_all()
			else:
				# Let it fall through to unicode handling
				if event.unicode > 31 and event.unicode < 127:
					if has_selection():
						delete_selection()
					var char_str = char(event.unicode)
					insert_character(char_str)
		KEY_C:
			if ctrl_pressed:
				copy_selection()
			else:
				# Let it fall through to unicode handling
				if event.unicode > 31 and event.unicode < 127:
					if has_selection():
						delete_selection()
					var char_str = char(event.unicode)
					insert_character(char_str)
		KEY_V:
			if ctrl_pressed:
				paste_from_clipboard()
			else:
				# Let it fall through to unicode handling
				if event.unicode > 31 and event.unicode < 127:
					if has_selection():
						delete_selection()
					var char_str = char(event.unicode)
					insert_character(char_str)
		KEY_Z:
			if ctrl_pressed:
				if shift_pressed:
					redo()  # Ctrl+Shift+Z for redo
				else:
					undo()  # Ctrl+Z for undo
		KEY_Y:
			if ctrl_pressed:
				redo()  # Ctrl+Y for redo (alternative)
		KEY_X:
			if ctrl_pressed and shift_pressed:
				# Ctrl+Shift+X for strikethrough
				toggle_formatting_type("strikethrough")
			elif ctrl_pressed:
				cut_selection()
			else:
				# Let it fall through to unicode handling
				if event.unicode > 31 and event.unicode < 127:
					if has_selection():
						delete_selection()
					var char_str = char(event.unicode)
					insert_character(char_str)
		_:
			# Handle printable characters
			if event.unicode > 31 and event.unicode < 127:
				if has_selection():
					delete_selection()
				var char_str = char(event.unicode)
				insert_character(char_str)

func handle_mouse_input(event: InputEventMouseButton):
	if event.button_index == MOUSE_BUTTON_LEFT:
		# If context menu is visible and wasn't just shown, hide it and continue processing
		if context_menu.visible and not context_menu_just_shown:
			context_menu.hide()
		context_menu_just_shown = false
		
		grab_focus()
		
		# Check if click is in line number area
		if event.position.x < line_number_width:
			if event.pressed and event.double_click:
				# Double-click on line number - select entire line
				var line_number = get_line_number_at_y(event.position.y)
				select_entire_line(line_number)
				line_drag_active = false  # Reset drag state
				# Reset caret blinking animation
				cursor_visible = true
				cursor_blink_time = 0.0
				queue_redraw()
				return
			elif event.pressed:
				# Single click on line number - start line drag selection
				var line_number = get_line_number_at_y(event.position.y)
				line_drag_active = true
				line_drag_start_line = line_number
				select_entire_line(line_number)
				# Reset caret blinking animation
				cursor_visible = true
				cursor_blink_time = 0.0
				queue_redraw()
				return
			else:
				# Mouse release in line number area - end line drag
				line_drag_active = false
				return
		
		# Regular text area click handling
		line_drag_active = false  # Reset line drag state when clicking in text area
		var click_pos = get_text_position_at(event.position)
		if event.pressed:
			# Clear the context menu flag when actually clicking in text area
			context_menu_just_shown = false
			# Check for double-click
			if event.double_click:
				select_word_at_position(click_pos)
				# Reset caret blinking animation on double-click
				cursor_visible = true
				cursor_blink_time = 0.0
			else:
				cursor_position = click_pos
				# Clear any existing selection on click
				clear_selection()
				# Reset empty line selection flag for regular text clicks
				intentional_empty_line_selection = false
				# Store mouse down position for drag detection
				mouse_down_position = event.position
				# Capture mouse to continue tracking even outside bounds
				Input.set_default_cursor_shape(Input.CURSOR_IBEAM)
				# Reset caret blinking animation on click
				cursor_visible = true
				cursor_blink_time = 0.0
		else:
			# End selection on mouse up
			if selection_start == selection_end:
				clear_selection()
		queue_redraw()
	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		grab_focus()
		
		# Check if right-click is outside current selection
		var click_pos = get_text_position_at(event.position)
		var selection_active = has_selection()
		var click_in_selection = false
		
		if selection_active:
			var start_pos = min(selection_start, selection_end)
			var end_pos = max(selection_start, selection_end)
			click_in_selection = click_pos >= start_pos and click_pos <= end_pos
		
		# If clicking outside selection or no selection exists, move cursor and clear selection
		if not click_in_selection:
			cursor_position = click_pos
			clear_selection()
			queue_redraw()
		
		# Show custom context menu with offset at mouse tip level
		var mouse_global_pos = get_global_mouse_position()
		context_menu.position = mouse_global_pos + Vector2(-5, 0) - global_position
		context_menu.visible = true
		context_menu.move_to_front()
		context_menu_just_shown = true

func handle_mouse_motion(event: InputEventMouseMotion):
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if line_drag_active:
			# Handle line number drag selection with improved accuracy
			var current_line = get_line_number_at_y(event.position.y)
			
			# Only update if line actually changed to reduce flicker
			var text_content = get_text()
			var expected_start = min(line_drag_start_line, current_line)
			var expected_end = max(line_drag_start_line, current_line)
			
			# Check if selection needs updating
			var needs_update = false
			if selection_start == -1 or selection_end == -1:
				needs_update = true
			else:
				# Convert current selection back to line numbers to check if they changed
				var current_start_line = get_line_at_position(selection_start)
				var current_end_line = get_line_at_position(selection_end - 1) # -1 because selection_end is exclusive
				
				if current_start_line != expected_start or current_end_line != expected_end:
					needs_update = true
			
			if needs_update:
				select_line_range(line_drag_start_line, current_line)
				queue_redraw()
		else:
			# Handle regular text drag selection - only start if we've moved enough
			if selection_start == -1:
				# Check if we've moved far enough to start a selection
				var distance = event.position.distance_to(mouse_down_position)
				if distance >= drag_threshold:
					# Start new selection at original mouse down position
					var start_pos = get_text_position_at(mouse_down_position)
					
					selection_start = start_pos
					selection_end = start_pos
				else:
					# Not enough movement, don't start selection yet
					return
			
			# Handle regular text drag selection with better out-of-bounds handling
			var drag_pos = get_text_position_at_extended(event.position)
			
			# Always update selection_end (never change selection_start once set)
			selection_end = drag_pos
			cursor_position = drag_pos
			queue_redraw()

func get_text_position_at(visual_pos: Vector2) -> int:
	# Convert visual position back to text position using same logic as get_visual_position() but in reverse
	var line_data = get_line_data()
	var pos = text_margin
	pos.y -= scroll_offset  # Apply scroll offset to drawing position
	var current_text_pos = 0
	
	# If click is above text area, return position 0
	if visual_pos.y < text_margin.y:
		return 0
	
	# Find which line the click is on
	for line_info in line_data:
		var line_segments = line_info.segments
		var line_height_val = line_info.height
		var line_start_pos = current_text_pos
		
		# Calculate total length of this line
		var line_length = 0
		for segment_info in line_segments:
			line_length += segment_info.text.length()
		
		var line_end_pos = line_start_pos + line_length
		
		# Check if click is within this line's Y range
		if visual_pos.y >= pos.y and visual_pos.y < pos.y + line_height_val:
			# Found the correct line - now find X position within the line
			var line_x = pos.x
			var chars_processed = 0
			
			for segment_info in line_segments:
				var segment = segment_info.segment
				var text = segment_info.text
				var font = get_segment_font(segment)
				var segment_font_size = get_segment_font_size(segment)
				
				# If click is before this segment, return position at start of segment
				if visual_pos.x < line_x:
					return line_start_pos + chars_processed
				
				# Check positions within this segment using binary search approach
				for char_idx in range(text.length() + 1):  # +1 to include position after last character
					var partial_text = text.substr(0, char_idx)
					var partial_width = font.get_string_size(partial_text, HORIZONTAL_ALIGNMENT_LEFT, -1, segment_font_size).x
					var char_right_edge = line_x + partial_width
					
					if visual_pos.x <= char_right_edge:
						# Found the position - check which side of character
						if char_idx == 0:
							return line_start_pos + chars_processed
						else:
							var prev_partial_text = text.substr(0, char_idx - 1)
							var prev_partial_width = font.get_string_size(prev_partial_text, HORIZONTAL_ALIGNMENT_LEFT, -1, segment_font_size).x
							var char_left_edge = line_x + prev_partial_width
							var char_center = (char_left_edge + char_right_edge) / 2
							
							if visual_pos.x < char_center:
								return line_start_pos + chars_processed + char_idx - 1
							else:
								return line_start_pos + chars_processed + char_idx
				
				# Update position for next segment
				var segment_width = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, segment_font_size).x
				line_x += segment_width
				chars_processed += text.length()
			
			# Click was beyond the end of this line
			return line_end_pos
		
		# Move to next line
		pos.y += line_height_val
		current_text_pos = line_end_pos + 1  # +1 for newline character (if exists)
	
	# Click was below all text
	return get_total_text_length()

func get_text_position_at_extended(visual_pos: Vector2) -> int:
	# Extended version that handles out-of-bounds positions smoothly for selection
	var full_text = get_text()
	
	# Handle positions above text area
	if visual_pos.y < text_margin.y:
		return 0
	
	# Handle positions in line number area - clamp to start of line
	if visual_pos.x < text_margin.x:
		return get_line_start_at_y(visual_pos.y)
	
	# Handle positions below text area - return end of text
	if visual_pos.y > size.y:
		return full_text.length()
	
	# Handle positions to the right of text area - find end of line at that Y
	if visual_pos.x > size.x:
		return get_line_end_at_y(visual_pos.y)
	
	# For positions within bounds, use regular calculation
	return get_text_position_at(visual_pos)

func get_line_start_position(line_index: int) -> int:
	# Get the text position at the start of the given line (0-based)
	if line_index <= 0:
		return 0
	
	var full_text = get_text()
	var current_line = 0
	var pos = 0
	
	for i in range(full_text.length()):
		if current_line == line_index:
			return pos
		if full_text[i] == '\n':
			current_line += 1
			pos = i + 1
		else:
			if current_line < line_index:
				pos = i + 1
	
	return pos

func get_line_end_position(line_index: int) -> int:
	# Get the text position at the end of the given line (0-based)
	var full_text = get_text()
	var current_line = 0
	var line_start = 0
	
	for i in range(full_text.length()):
		if current_line == line_index:
			# Found the target line, now find its end
			for j in range(i, full_text.length()):
				if full_text[j] == '\n':
					return j  # Return position just before newline
			return full_text.length()  # End of text if no newline found
		elif full_text[i] == '\n':
			current_line += 1
			line_start = i + 1
	
	# If line_index is beyond available lines, return end of text
	return full_text.length()

func move_cursor(delta: int):
	cursor_position = max(0, min(get_total_text_length(), cursor_position + delta))
	cursor_visible = true
	cursor_blink_time = 0.0
	queue_redraw()

func insert_character(char: String):
	save_state()  # Save state before modification
	
	var segment_info = find_segment_at_position(cursor_position)
	var segment = segment_info.segment
	var local_pos = segment_info.local_position
	
	# Insert character with current formatting
	segment.text = segment.text.insert(local_pos, char)
	cursor_position += 1
	
	# Invalidate cache
	invalidate_cache()
	
	text_changed.emit()
	queue_redraw()

func delete_character(delta: int):
	save_state()  # Save state before modification
	
	if delta < 0 and cursor_position > 0:
		# Backspace
		var segment_info = find_segment_at_position(cursor_position - 1)
		var segment = segment_info.segment
		var local_pos = segment_info.local_position
		
		segment.text = segment.text.erase(local_pos, 1)
		cursor_position -= 1
	elif delta > 0 and cursor_position < get_total_text_length():
		# Delete
		var segment_info = find_segment_at_position(cursor_position)
		var segment = segment_info.segment
		var local_pos = segment_info.local_position
		
		segment.text = segment.text.erase(local_pos, 1)
	
	# Invalidate cache
	invalidate_cache()
	
	text_changed.emit()
	queue_redraw()

func delete_word(delta: int):
	save_state()  # Save state before modification
	
	var text_content = get_text()
	var start_pos = cursor_position
	var end_pos = cursor_position
	
	if delta < 0:
		# Delete word backwards (CTRL+Backspace)
		if cursor_position > 0:
			# Move backward to find word boundary
			var pos = cursor_position - 1
			
			# Skip whitespace first
			while pos >= 0 and (text_content[pos] == ' ' or text_content[pos] == '\t' or text_content[pos] == '\n'):
				pos -= 1
			
			# Then skip word characters
			while pos >= 0 and is_word_char(text_content[pos]):
				pos -= 1
			
			start_pos = pos + 1
			end_pos = cursor_position
	elif delta > 0:
		# Delete word forwards (CTRL+Delete)
		if cursor_position < text_content.length():
			# Move forward to find word boundary
			var pos = cursor_position
			
			# Skip whitespace first
			while pos < text_content.length() and (text_content[pos] == ' ' or text_content[pos] == '\t' or text_content[pos] == '\n'):
				pos += 1
			
			# Then skip word characters
			while pos < text_content.length() and is_word_char(text_content[pos]):
				pos += 1
			
			start_pos = cursor_position
			end_pos = pos
	
	# Delete the range if we found a word boundary
	if start_pos != end_pos:
		# Create a temporary selection and delete it
		var old_selection_start = selection_start
		var old_selection_end = selection_end
		
		selection_start = start_pos
		selection_end = end_pos
		delete_selection()
		
		# Restore original selection state
		selection_start = old_selection_start
		selection_end = old_selection_end

func find_segment_at_position(pos: int) -> Dictionary:
	# Ensure we have segments and valid position
	if segments.is_empty():
		segments = [TextSegment.new("")]
	
	pos = clamp(pos, 0, get_total_text_length())
	var current_pos = 0
	
	for i in range(segments.size()):
		var segment = segments[i]
		if current_pos + segment.text.length() > pos:
			var local_pos = clamp(pos - current_pos, 0, segment.text.length())
			return {"segment": segment, "segment_index": i, "local_position": local_pos}
		current_pos += segment.text.length()
	
	# Return last segment if position is at end
	var last_segment = segments[-1]
	return {"segment": last_segment, "segment_index": segments.size() - 1, "local_position": last_segment.text.length()}

func get_total_text_length() -> int:
	var total = 0
	for segment in segments:
		total += segment.text.length()
	return total

func apply_formatting(bold: bool = false, italic: bool = false, strikethrough: bool = false, code: bool = false):
	current_format.bold = bold
	current_format.italic = italic
	current_format.strikethrough = strikethrough
	current_format.code = code
	
	# If there's a selection, apply formatting to selected text
	if selection_start != -1 and selection_end != -1:
		apply_formatting_to_selection(bold, italic, strikethrough, code)
	
	queue_redraw()

func toggle_formatting_type(format_type: String):
	if not has_selection():
		# No selection - just toggle current format for new text
		match format_type:
			"bold":
				current_format.bold = not current_format.bold
			"italic":
				current_format.italic = not current_format.italic
			"strikethrough":
				current_format.strikethrough = not current_format.strikethrough
			"code":
				current_format.code = not current_format.code
				# Code formatting is exclusive
				if current_format.code:
					current_format.bold = false
					current_format.italic = false
					current_format.strikethrough = false
		return
	
	# Has selection - check current state and toggle
	var start_pos = min(selection_start, selection_end)
	var end_pos = max(selection_start, selection_end)
	
	# Check if selected text already has this formatting
	var has_formatting = check_selection_has_formatting(format_type)
	
	# Apply opposite formatting
	match format_type:
		"bold":
			toggle_specific_formatting_in_selection("bold", not has_formatting)
		"italic":
			toggle_specific_formatting_in_selection("italic", not has_formatting)
		"strikethrough":
			toggle_specific_formatting_in_selection("strikethrough", not has_formatting)
		"code":
			apply_formatting_to_selection(false, false, false, not has_formatting)
	
	queue_redraw()

func check_selection_has_formatting(format_type: String) -> bool:
	if not has_selection():
		return false
	
	var start_pos = min(selection_start, selection_end)
	var end_pos = max(selection_start, selection_end)
	var current_pos = 0
	
	# Check if any part of selection has this formatting
	for segment in segments:
		var segment_start = current_pos
		var segment_end = current_pos + segment.text.length()
		
		# Check if this segment overlaps with selection
		if segment_end > start_pos and segment_start < end_pos:
			match format_type:
				"bold":
					if segment.bold:
						return true
				"italic":
					if segment.italic:
						return true
				"strikethrough":
					if segment.strikethrough:
						return true
				"code":
					if segment.code:
						return true
		
		current_pos += segment.text.length()
	
	return false

func toggle_specific_formatting_in_selection(format_type: String, enable: bool):
	if not has_selection():
		return
	
	save_state()  # Save state before modification
	
	var start_pos = min(selection_start, selection_end)
	var end_pos = max(selection_start, selection_end)
	
	var new_segments: Array[TextSegment] = []
	var current_pos = 0
	
	for segment in segments:
		var segment_start = current_pos
		var segment_end = current_pos + segment.text.length()
		
		if segment_end <= start_pos or segment_start >= end_pos:
			# Segment is outside selection - keep unchanged
			new_segments.append(segment.copy())
		elif segment_start >= start_pos and segment_end <= end_pos:
			# Segment is completely within selection - toggle specific formatting
			var new_segment = segment.copy()
			match format_type:
				"bold":
					new_segment.bold = enable
				"italic":
					new_segment.italic = enable
				"strikethrough":
					new_segment.strikethrough = enable
			new_segments.append(new_segment)
		else:
			# Segment is partially within selection - split it
			if segment_start < start_pos:
				# Part before selection
				var before_segment = segment.copy()
				before_segment.text = segment.text.substr(0, start_pos - segment_start)
				new_segments.append(before_segment)
			
			# Part within selection
			var selection_start_in_segment = max(0, start_pos - segment_start)
			var selection_end_in_segment = min(segment.text.length(), end_pos - segment_start)
			var selected_text = segment.text.substr(selection_start_in_segment, selection_end_in_segment - selection_start_in_segment)
			
			if selected_text.length() > 0:
				var selected_segment = segment.copy()
				selected_segment.text = selected_text
				match format_type:
					"bold":
						selected_segment.bold = enable
					"italic":
						selected_segment.italic = enable
					"strikethrough":
						selected_segment.strikethrough = enable
				new_segments.append(selected_segment)
			
			if segment_end > end_pos:
				# Part after selection
				var after_segment = segment.copy()
				after_segment.text = segment.text.substr(end_pos - segment_start)
				new_segments.append(after_segment)
		
		current_pos += segment.text.length()
	
	segments = new_segments
	
	# Clear selection after formatting to prevent coordinate mismatch with new segment structure
	clear_selection()
	
	# Invalidate cache
	invalidate_cache()
	
	text_changed.emit()
	queue_redraw()

func apply_formatting_to_selection(bold: bool, italic: bool, strikethrough: bool, code: bool):
	if not has_selection():
		return
	
	save_state()  # Save state before modification
	
	var start_pos = min(selection_start, selection_end)
	var end_pos = max(selection_start, selection_end)
	
	var new_segments: Array[TextSegment] = []
	var current_pos = 0
	
	for segment in segments:
		var segment_start = current_pos
		var segment_end = current_pos + segment.text.length()
		
		if segment_end <= start_pos or segment_start >= end_pos:
			# Segment is outside selection - keep unchanged
			new_segments.append(segment.copy())
		elif segment_start >= start_pos and segment_end <= end_pos:
			# Segment is completely within selection - apply formatting
			var new_segment = segment.copy()
			new_segment.bold = bold
			new_segment.italic = italic
			new_segment.strikethrough = strikethrough
			new_segment.code = code
			new_segments.append(new_segment)
		else:
			# Segment is partially within selection - split it
			if segment_start < start_pos:
				# Part before selection
				var before_segment = segment.copy()
				before_segment.text = segment.text.substr(0, start_pos - segment_start)
				new_segments.append(before_segment)
			
			# Part within selection
			var selection_start_in_segment = max(0, start_pos - segment_start)
			var selection_end_in_segment = min(segment.text.length(), end_pos - segment_start)
			var selected_text = segment.text.substr(selection_start_in_segment, selection_end_in_segment - selection_start_in_segment)
			
			if selected_text.length() > 0:
				var selected_segment = segment.copy()
				selected_segment.text = selected_text
				selected_segment.bold = bold
				selected_segment.italic = italic
				selected_segment.strikethrough = strikethrough
				selected_segment.code = code
				new_segments.append(selected_segment)
			
			if segment_end > end_pos:
				# Part after selection
				var after_segment = segment.copy()
				after_segment.text = segment.text.substr(end_pos - segment_start)
				new_segments.append(after_segment)
		
		current_pos += segment.text.length()
	
	segments = new_segments
	
	# Clear selection after formatting to prevent coordinate mismatch with new segment structure
	clear_selection()
	
	# Invalidate cache
	invalidate_cache()
	
	text_changed.emit()
	queue_redraw()

func get_text() -> String:
	var result = ""
	for segment in segments:
		result += segment.text
	return result

func set_text(text: String):
	segments = [TextSegment.new(text)]
	cursor_position = 0
	invalidate_cache()
	queue_redraw()

# Selection functions
func has_selection() -> bool:
	if selection_start == -1 or selection_end == -1:
		return false
	
	# Ensure selection bounds are valid
	var text_length = get_total_text_length()
	var start = clamp(selection_start, 0, text_length)
	var end = clamp(selection_end, 0, text_length)
	
	return start != end

func start_selection():
	if selection_start == -1:
		selection_start = cursor_position

func update_selection():
	selection_end = cursor_position

func clear_selection():
	selection_start = -1
	selection_end = -1
	intentional_empty_line_selection = false
	queue_redraw()

func select_all():
	selection_start = 0
	selection_end = get_total_text_length()
	cursor_position = selection_end
	queue_redraw()

func delete_selection():
	if not has_selection():
		return
	
	save_state()  # Save state before modification
	
	var start_pos = min(selection_start, selection_end)
	var end_pos = max(selection_start, selection_end)
	
	# Find segments affected by deletion
	var new_segments: Array[TextSegment] = []
	var current_pos = 0
	
	for segment in segments:
		var segment_start = current_pos
		var segment_end = current_pos + segment.text.length()
		
		if segment_end <= start_pos:
			# Segment is completely before selection - keep it
			new_segments.append(segment.copy())
		elif segment_start >= end_pos:
			# Segment is completely after selection - keep it
			new_segments.append(segment.copy())
		elif segment_start < start_pos and segment_end > end_pos:
			# Selection is within this segment - split it
			var before_text = segment.text.substr(0, start_pos - segment_start)
			var after_text = segment.text.substr(end_pos - segment_start)
			var new_segment = segment.copy()
			new_segment.text = before_text + after_text
			new_segments.append(new_segment)
		elif segment_start < start_pos and segment_end > start_pos:
			# Selection starts within this segment
			var before_text = segment.text.substr(0, start_pos - segment_start)
			if before_text.length() > 0:
				var new_segment = segment.copy()
				new_segment.text = before_text
				new_segments.append(new_segment)
		elif segment_start < end_pos and segment_end > end_pos:
			# Selection ends within this segment
			var after_text = segment.text.substr(end_pos - segment_start)
			if after_text.length() > 0:
				var new_segment = segment.copy()
				new_segment.text = after_text
				new_segments.append(new_segment)
		# Segments completely within selection are deleted (not added)
		
		current_pos += segment.text.length()
	
	# Ensure we have at least one segment
	if new_segments.is_empty():
		new_segments.append(TextSegment.new(""))
	
	segments = new_segments
	
	# Clean up empty segments and merge adjacent segments with same formatting
	cleanup_segments()
	
	cursor_position = start_pos
	clear_selection()
	
	# Invalidate cache
	invalidate_cache()
	
	text_changed.emit()

func get_selected_text() -> String:
	if not has_selection():
		return ""
	
	var start_pos = min(selection_start, selection_end)
	var end_pos = max(selection_start, selection_end)
	var text_content = get_text()
	return text_content.substr(start_pos, end_pos - start_pos)

# Clipboard functions
func copy_selection():
	if has_selection():
		DisplayServer.clipboard_set(get_selected_text())

func cut_selection():
	if has_selection():
		save_state()  # Save state before modification
		copy_selection()
		delete_selection()

func paste_from_clipboard():
	save_state()  # Save state before modification
	
	var clipboard_text = DisplayServer.clipboard_get()
	if clipboard_text.length() > 0:
		if has_selection():
			delete_selection()
		
		# Insert entire text as single operation without calling save_state for each character
		var segment_info = find_segment_at_position(cursor_position)
		var segment = segment_info.segment
		var local_pos = segment_info.local_position
		
		# Insert clipboard text with current formatting
		segment.text = segment.text.insert(local_pos, clipboard_text)
		cursor_position += clipboard_text.length()
		
		# Invalidate cache
		invalidate_cache()
		
		text_changed.emit()
		queue_redraw()

# Navigation functions
func move_cursor_to_line_start():
	# Move cursor to start of current line
	var text_content = get_text()
	var pos = cursor_position
	while pos > 0 and text_content[pos - 1] != '\n':
		pos -= 1
	cursor_position = pos
	queue_redraw()

func move_cursor_to_line_end():
	# Move cursor to end of current line
	var text_content = get_text()
	var pos = cursor_position
	while pos < text_content.length() and text_content[pos] != '\n':
		pos += 1
	cursor_position = pos
	queue_redraw()

func _can_drop_data(position, data):
	return false

func _drop_data(position, data):
	pass


func select_word_at_position(pos: int):
	var text_content = get_text()
	if text_content.is_empty():
		return
	
	pos = clamp(pos, 0, text_content.length())
	
	# Find word boundaries
	var word_start = pos
	var word_end = pos
	
	# Find start of word
	while word_start > 0 and is_word_char(text_content[word_start - 1]):
		word_start -= 1
	
	# Find end of word
	while word_end < text_content.length() and is_word_char(text_content[word_end]):
		word_end += 1
	
	# Select the word
	if word_start < word_end:
		selection_start = word_start
		selection_end = word_end
		cursor_position = word_end
		queue_redraw()

func is_word_char(char: String) -> bool:
	# Consider alphanumeric characters and underscore as word characters
	var code = char.unicode_at(0)
	return (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95

func get_line_number_at_y(y_pos: float) -> int:
	# Convert Y position to line number (1-based)
	# Handle edge cases and bounds properly
	
	# If above text area, return line 1
	if y_pos < text_margin.y:
		return 1
	
	# Use line data for accurate positioning with dynamic heights
	var line_data = get_line_data()
	var current_y = text_margin.y - scroll_offset  # Apply scroll offset
	
	for i in range(line_data.size()):
		var line_info = line_data[i]
		var line_height_val = line_info.height
		
		# Check if Y position is within this line
		if y_pos >= current_y and y_pos < current_y + line_height_val:
			return i + 1  # Return 1-based line number
		
		current_y += line_height_val
	
	# If beyond all lines, return the last line number
	return max(1, line_data.size())

func get_line_at_position(text_pos: int) -> int:
	# Convert text position to line number (1-based)
	var text_content = get_text()
	var line_number = 1
	
	for i in range(min(text_pos, text_content.length())):
		if text_content[i] == '\n':
			line_number += 1
	
	return line_number

# Undo/Redo system functions
func save_state():
	# Save current state to undo stack
	var state = UndoState.new(segments, cursor_position, selection_start, selection_end)
	undo_stack.append(state)
	
	# Limit undo stack size
	if undo_stack.size() > max_undo_steps:
		undo_stack.pop_front()
	
	# Clear redo stack when new action is performed
	redo_stack.clear()

func undo():
	if undo_stack.is_empty():
		return
	
	# Save current state to redo stack
	var current_state = UndoState.new(segments, cursor_position, selection_start, selection_end)
	redo_stack.append(current_state)
	
	# Restore previous state
	var prev_state = undo_stack.pop_back()
	restore_state(prev_state)

func redo():
	if redo_stack.is_empty():
		return
	
	# Save current state to undo stack
	var current_state = UndoState.new(segments, cursor_position, selection_start, selection_end)
	undo_stack.append(current_state)
	
	# Restore next state
	var next_state = redo_stack.pop_back()
	restore_state(next_state)

func restore_state(state: UndoState):
	# Restore segments
	segments.clear()
	for seg in state.segments_data:
		segments.append(seg.copy())
	
	# Restore cursor and selection
	cursor_position = state.cursor_pos
	selection_start = state.selection_start_pos
	selection_end = state.selection_end_pos
	
	# Invalidate cache since content changed
	invalidate_cache()
	
	# Update display
	text_changed.emit()
	queue_redraw()

func select_entire_line(line_number: int):
	# Select the entire line (1-based line number)
	var text_content = get_text()
	if text_content.is_empty():
		selection_start = 0
		selection_end = 0
		cursor_position = 0
		queue_redraw()
		return
	
	# Build line positions array for more reliable line finding
	var line_starts = [0]  # Start positions of each line
	for i in range(text_content.length()):
		if text_content[i] == '\n':
			line_starts.append(i + 1)
	
	# Check if line_number is valid
	if line_number < 1 or line_number > line_starts.size():
		# Invalid line number - clear selection
		selection_start = -1
		selection_end = -1
		cursor_position = 0
		queue_redraw()
		return
	
	# Get line boundaries
	var line_start = line_starts[line_number - 1]  # Convert to 0-based
	var line_end = line_start
	
	# Find end of this line
	if line_number < line_starts.size():
		# Not the last line - end is just before next line start
		line_end = line_starts[line_number] - 1  # -1 to exclude the newline
	else:
		# Last line - go to end of text
		line_end = text_content.length()
	
	# Set selection
	selection_start = line_start
	selection_end = line_end
	cursor_position = line_end
	
	# Set flag for intentional empty line selection if this is an empty line
	intentional_empty_line_selection = (line_start == line_end)
	
	queue_redraw()

func select_line_range(start_line: int, end_line: int):
	# Select a range of lines (1-based line numbers) using same logic as select_entire_line
	var text_content = get_text()
	if text_content.is_empty():
		selection_start = 0
		selection_end = 0
		cursor_position = 0
		queue_redraw()
		return
	
	# Build line positions array - same as select_entire_line
	var line_starts = [0]
	for i in range(text_content.length()):
		if text_content[i] == '\n':
			line_starts.append(i + 1)
	
	# Clamp line numbers to valid range
	start_line = clamp(start_line, 1, line_starts.size())
	end_line = clamp(end_line, 1, line_starts.size())
	
	# Determine direction
	var first_line = min(start_line, end_line)
	var last_line = max(start_line, end_line)
	
	# Get start position of first line
	var range_start = line_starts[first_line - 1]
	
	# Get end position of last line - fixed for multiline selections
	var range_end
	if first_line == last_line:
		# Single line selection - use original logic to exclude newline
		if last_line < line_starts.size():
			range_end = line_starts[last_line] - 1  # -1 to exclude the newline
		else:
			range_end = text_content.length()
	else:
		# Multi-line selection - include newlines to properly select empty lines
		if last_line < line_starts.size():
			range_end = line_starts[last_line]  # Include newline for multiline selection
		else:
			range_end = text_content.length()
	
	# Set selection
	selection_start = range_start
	selection_end = range_end
	
	# For line selections, position cursor at end of last selected line (not including newlines)
	if first_line == last_line:
		# Single line - cursor at end of selection
		cursor_position = range_end
	else:
		# Multi-line - cursor should be at end of last line's content, not including trailing newlines
		if last_line < line_starts.size():
			# Not the last line - position cursor at end of last line's content
			cursor_position = line_starts[last_line] - 1  # -1 to exclude the newline
		else:
			# Last line - cursor at end of text
			cursor_position = text_content.length()
	
	queue_redraw()

# New formatting insertion functions
func insert_heading(level: int):
	save_state()
	
	# Move to start of current line
	move_cursor_to_line_start()
	var line_start = cursor_position
	
	# Find end of current line
	var text_content = get_text()
	var line_end = cursor_position
	while line_end < text_content.length() and text_content[line_end] != '\n':
		line_end += 1
	
	# Select the entire line
	selection_start = line_start
	selection_end = line_end
	
	# Apply heading formatting to selected text
	if has_selection():
		var start_pos = min(selection_start, selection_end)
		var end_pos = max(selection_start, selection_end)
		var new_segments: Array[TextSegment] = []
		var current_pos = 0
		
		for segment in segments:
			var segment_start = current_pos
			var segment_end = current_pos + segment.text.length()
			
			if segment_end <= start_pos or segment_start >= end_pos:
				# Segment is outside selection - keep unchanged
				new_segments.append(segment.copy())
			elif segment_start >= start_pos and segment_end <= end_pos:
				# Segment is completely within selection - make it a heading
				var new_segment = segment.copy()
				new_segment.heading_level = level
				# Clear other exclusive formatting
				new_segment.code = false
				new_segments.append(new_segment)
			else:
				# Segment is partially within selection - split it
				if segment_start < start_pos:
					# Part before selection
					var before_segment = segment.copy()
					before_segment.text = segment.text.substr(0, start_pos - segment_start)
					new_segments.append(before_segment)
				
				# Part within selection
				var selection_start_in_segment = max(0, start_pos - segment_start)
				var selection_end_in_segment = min(segment.text.length(), end_pos - segment_start)
				var selected_text = segment.text.substr(selection_start_in_segment, selection_end_in_segment - selection_start_in_segment)
				
				if selected_text.length() > 0:
					var selected_segment = segment.copy()
					selected_segment.text = selected_text
					selected_segment.heading_level = level
					selected_segment.code = false
					new_segments.append(selected_segment)
				
				if segment_end > end_pos:
					# Part after selection
					var after_segment = segment.copy()
					after_segment.text = segment.text.substr(end_pos - segment_start)
					new_segments.append(after_segment)
			
			current_pos += segment.text.length()
		
		segments = new_segments
		clear_selection()
		text_changed.emit()
		queue_redraw()

func insert_list_item(type: String):
	save_state()
	move_cursor_to_line_start()
	
	var prefix = ""
	match type:
		"bullet":
			prefix = "• "
		"numbered":
			prefix = "1. "
		"checklist":
			prefix = "- [ ] "
	
	# Insert the prefix
	var segment_info = find_segment_at_position(cursor_position)
	var segment = segment_info.segment
	var local_pos = segment_info.local_position
	
	segment.text = segment.text.insert(local_pos, prefix)
	cursor_position += prefix.length()
	
	text_changed.emit()
	queue_redraw()

func insert_blockquote():
	save_state()
	move_cursor_to_line_start()
	
	# Insert blockquote prefix
	var segment_info = find_segment_at_position(cursor_position)
	var segment = segment_info.segment
	var local_pos = segment_info.local_position
	
	segment.text = segment.text.insert(local_pos, "> ")
	cursor_position += 2
	
	text_changed.emit()
	queue_redraw()

func insert_code_block():
	save_state()
	
	# Insert code block markers
	var code_block = "```\n\n```"
	var segment_info = find_segment_at_position(cursor_position)
	var segment = segment_info.segment
	var local_pos = segment_info.local_position
	
	segment.text = segment.text.insert(local_pos, code_block)
	cursor_position += 4  # Position cursor inside the code block
	
	text_changed.emit()
	queue_redraw()

func insert_horizontal_rule():
	save_state()
	
	# Insert horizontal rule
	var hr = "\n---\n"
	var segment_info = find_segment_at_position(cursor_position)
	var segment = segment_info.segment
	var local_pos = segment_info.local_position
	
	segment.text = segment.text.insert(local_pos, hr)
	cursor_position += hr.length()
	
	text_changed.emit()
	queue_redraw()

func insert_link():
	save_state()
	
	var link_text = "[Link Text](https://example.com)"
	if has_selection():
		# Use selected text as link text
		var selected = get_selected_text()
		link_text = "[" + selected + "](https://example.com)"
		delete_selection()
	
	var segment_info = find_segment_at_position(cursor_position)
	var segment = segment_info.segment
	var local_pos = segment_info.local_position
	
	segment.text = segment.text.insert(local_pos, link_text)
	cursor_position += link_text.length()
	
	text_changed.emit()
	queue_redraw()

func insert_image():
	save_state()
	
	var image_text = "![Alt Text](image.png)"
	var segment_info = find_segment_at_position(cursor_position)
	var segment = segment_info.segment
	var local_pos = segment_info.local_position
	
	segment.text = segment.text.insert(local_pos, image_text)
	cursor_position += image_text.length()
	
	text_changed.emit()
	queue_redraw()

func insert_table():
	save_state()
	
	var table_text = """
| Header 1 | Header 2 | Header 3 |
|----------|----------|----------|
| Cell 1   | Cell 2   | Cell 3   |
| Cell 4   | Cell 5   | Cell 6   |
"""
	var segment_info = find_segment_at_position(cursor_position)
	var segment = segment_info.segment
	var local_pos = segment_info.local_position
	
	segment.text = segment.text.insert(local_pos, table_text)
	cursor_position += table_text.length()
	
	text_changed.emit()
	queue_redraw()

# Scrolling functions
func scroll_up():
	var scroll_speed = line_height * 3  # Scroll 3 lines at a time
	scroll_offset = max(0, scroll_offset - scroll_speed)
	queue_redraw()

func scroll_down():
	var max_scroll = max(0, total_content_height - size.y)
	var scroll_speed = line_height * 3  # Scroll 3 lines at a time
	scroll_offset = min(max_scroll, scroll_offset + scroll_speed)
	queue_redraw()

func clamp_scroll_offset():
	var max_scroll = max(0, total_content_height - size.y)
	scroll_offset = clamp(scroll_offset, 0, max_scroll)
	queue_redraw()