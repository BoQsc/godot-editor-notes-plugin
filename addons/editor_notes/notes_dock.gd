@tool
extends Control

const RichEditor = preload("res://addons/editor_notes/rich_editor.gd")

var rich_editor: RichEditor
var render_display: RichTextLabel  # Original render mode
var render_container: ScrollContainer  # Container for render content with images
var custom_render_container: VBoxContainer  # Custom container for mixed text/image content
var image_overlays: Array[TextureRect] = []  # Track image overlay controls
var created_overlays: Dictionary = {}  # Track which images we've already created overlays for
var render_context_menu: PopupMenu  # Context menu for render mode
var current_mode: int = 1  # 0 = source, 1 = render
var mode_toggle_btn: Button

# All buttons - will be found manually
var bold_btn: Button
var italic_btn: Button
var strikethrough_btn: Button
var code_btn: Button
var heading_btn: MenuButton
var list_btn: MenuButton
var quote_btn: Button
var code_block_btn: Button
var hr_btn: Button
var link_btn: Button
var image_btn: Button
var table_btn: Button
var clear_btn: Button

const SAVE_PATH = "res://README.md"
var file_monitor_timer: Timer
var last_modified_time: int = 0

func _ready():
	setup_rich_editor()
	setup_render_display()
	setup_markdown_toolbar()  # New markdown-based toolbar
	setup_file_monitoring()
	load_notes()
	set_mode(current_mode)  # Set initial mode

func setup_rich_editor():
	# Create the rich editor
	rich_editor = RichEditor.new()
	rich_editor.name = "RichEditor"
	rich_editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rich_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Ensure clipping is enabled
	rich_editor.clip_contents = true
	
	# Set proper mouse filter for dock integration
	rich_editor.mouse_filter = Control.MOUSE_FILTER_STOP
	
	# Force the control to respect container bounds
	rich_editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rich_editor.custom_minimum_size = Vector2(0, 200)  # Minimum height for usability
	
	# Add to the main VBox container (which is now the root)
	add_child(rich_editor)
	
	# Explicitly ensure toolbar and header stay on top
	move_child($Header, 0)
	move_child($Toolbar, 1)
	move_child(rich_editor, 2)
	
	# Connect signals
	rich_editor.text_changed.connect(_on_text_changed)

func setup_render_display():
	# Create the original render display (RichTextLabel)
	render_display = RichTextLabel.new()
	render_display.name = "RenderDisplay"
	render_display.size_flags_vertical = Control.SIZE_EXPAND_FILL
	render_display.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	render_display.clip_contents = true
	render_display.bbcode_enabled = true
	render_display.scroll_following = false
	
	# Enable text selection in render mode
	render_display.selection_enabled = true
	
	# Enable clickable links
	render_display.meta_clicked.connect(_on_link_clicked)
	
	# Try to get Godot's editor monospace font for better code rendering
	var editor_settings = EditorInterface.get_editor_settings()
	if editor_settings:
		var code_font = editor_settings.get_setting("interface/editor/code_font")
		if code_font:
			render_display.add_theme_font_override("mono_font", code_font)
	
	# Set proper mouse filter for dock integration
	render_display.mouse_filter = Control.MOUSE_FILTER_STOP
	
	# Force the control to respect container bounds
	render_display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	render_display.custom_minimum_size = Vector2(0, 200)  # Minimum height for usability
	
	# Setup context menu for render display
	setup_render_context_menu()
	
	# Add to main container
	add_child(render_display)
	
	# Ensure proper z-order
	move_child($Header, 0)
	move_child($Toolbar, 1)
	move_child(rich_editor, 2)
	move_child(render_display, 3)


func setup_legacy_toolbar():
	# LEGACY: Find all toolbar buttons manually - this is the old rich text approach
	bold_btn = get_node_or_null("Toolbar/BoldBtn")
	italic_btn = get_node_or_null("Toolbar/ItalicBtn")
	strikethrough_btn = get_node_or_null("Toolbar/StrikethroughBtn")
	code_btn = get_node_or_null("Toolbar/CodeBtn")
	heading_btn = get_node_or_null("Toolbar/HeadingBtn")
	list_btn = get_node_or_null("Toolbar/ListBtn")
	quote_btn = get_node_or_null("Toolbar/QuoteBtn")
	code_block_btn = get_node_or_null("Toolbar/CodeBlockBtn")
	hr_btn = get_node_or_null("Toolbar/HRBtn")
	link_btn = get_node_or_null("Toolbar/LinkBtn")
	image_btn = get_node_or_null("Toolbar/ImageBtn")
	table_btn = get_node_or_null("Toolbar/TableBtn")
	clear_btn = get_node_or_null("Toolbar/ClearBtn")
	
	# Formatting buttons - with null checks
	if bold_btn:
		bold_btn.pressed.connect(func(): toggle_formatting_legacy("bold"))
	else:
		print("ERROR: bold_btn is null!")
	
	if italic_btn:
		italic_btn.pressed.connect(func(): toggle_formatting_legacy("italic"))
	if strikethrough_btn:
		strikethrough_btn.pressed.connect(func(): toggle_formatting_legacy("strikethrough"))
	if code_btn:
		code_btn.pressed.connect(func(): toggle_formatting_legacy("code"))
	
	# Setup heading menu
	setup_heading_menu()
	
	# Setup list menu  
	setup_list_menu()
	
	# Structure buttons - with null checks
	if quote_btn:
		quote_btn.pressed.connect(_insert_blockquote)
	if code_block_btn:
		code_block_btn.pressed.connect(_insert_code_block)
	if hr_btn:
		hr_btn.pressed.connect(_insert_horizontal_rule)
	
	# Insert buttons - with null checks
	if link_btn:
		link_btn.pressed.connect(_insert_link)
	if image_btn:
		image_btn.pressed.connect(_insert_image)
	if table_btn:
		table_btn.pressed.connect(_insert_table)
	if clear_btn:
		clear_btn.pressed.connect(_clear_all)

func setup_markdown_toolbar():
	# NEW: Markdown-based toolbar - inserts markdown syntax instead of rich formatting
	
	# Find all toolbar buttons manually
	bold_btn = get_node_or_null("Toolbar/BoldBtn")
	italic_btn = get_node_or_null("Toolbar/ItalicBtn")
	strikethrough_btn = get_node_or_null("Toolbar/StrikethroughBtn")
	code_btn = get_node_or_null("Toolbar/CodeBtn")
	heading_btn = get_node_or_null("Toolbar/HeadingBtn")
	list_btn = get_node_or_null("Toolbar/ListBtn")
	quote_btn = get_node_or_null("Toolbar/QuoteBtn")
	code_block_btn = get_node_or_null("Toolbar/CodeBlockBtn")
	hr_btn = get_node_or_null("Toolbar/HRBtn")
	link_btn = get_node_or_null("Toolbar/LinkBtn")
	image_btn = get_node_or_null("Toolbar/ImageBtn")
	table_btn = get_node_or_null("Toolbar/TableBtn")
	clear_btn = get_node_or_null("Toolbar/ClearBtn")
	mode_toggle_btn = get_node_or_null("Toolbar/ModeToggleBtn")
	
	# Add transparent normal state to all buttons
	add_transparent_normal_style(bold_btn)
	add_transparent_normal_style(italic_btn)
	add_transparent_normal_style(strikethrough_btn)
	add_transparent_normal_style(code_btn)
	add_transparent_normal_style(heading_btn)
	add_transparent_normal_style(list_btn)
	add_transparent_normal_style(quote_btn)
	add_transparent_normal_style(code_block_btn)
	add_transparent_normal_style(hr_btn)
	add_transparent_normal_style(link_btn)
	add_transparent_normal_style(image_btn)
	add_transparent_normal_style(table_btn)
	add_transparent_normal_style(clear_btn)
	add_transparent_normal_style(mode_toggle_btn)
	
	# Connect formatting buttons that work in both modes
	if bold_btn:
		bold_btn.pressed.connect(_apply_bold_formatting)
	if italic_btn:
		italic_btn.pressed.connect(_apply_italic_formatting)
	if strikethrough_btn:
		strikethrough_btn.pressed.connect(_apply_strikethrough_formatting)
	if code_btn:
		code_btn.pressed.connect(_apply_code_formatting)
	
	# Setup heading menu for markdown
	setup_markdown_heading_menu()
	
	# Setup list menu for markdown
	setup_markdown_list_menu()
	
	# Structure buttons for markdown
	if quote_btn:
		quote_btn.pressed.connect(_insert_markdown_blockquote)
	if code_block_btn:
		code_block_btn.pressed.connect(_insert_markdown_code_block)
	if hr_btn:
		hr_btn.pressed.connect(_insert_markdown_horizontal_rule)
	
	# Insert buttons for markdown
	if link_btn:
		link_btn.pressed.connect(_insert_markdown_link)
	if image_btn:
		image_btn.pressed.connect(_insert_markdown_image)
	if table_btn:
		table_btn.pressed.connect(_insert_markdown_table)
	if clear_btn:
		clear_btn.pressed.connect(_clear_all)
	
	# Mode toggle button
	if mode_toggle_btn:
		mode_toggle_btn.pressed.connect(_toggle_mode)

func insert_markdown_formatting(start_marker: String, end_marker: String = ""):
	if not rich_editor:
		return
	
	# If no end marker provided, use the same as start (for **bold**, *italic*, etc.)
	var end_mark = end_marker if end_marker != "" else start_marker
	
	if rich_editor.has_selection():
		# Wrap selected text with markdown syntax
		var selected_text = rich_editor.get_selected_text()
		var formatted_text = start_marker + selected_text + end_mark
		rich_editor.delete_selection()
		insert_text(formatted_text)
	else:
		# Insert markers at cursor position and place cursor between them
		var placeholder = "text"
		var formatted_text = start_marker + placeholder + end_mark
		insert_text(formatted_text)
		# Move cursor to select the placeholder
		var cursor_pos = rich_editor.cursor_position
		rich_editor.cursor_position = cursor_pos - placeholder.length() - end_mark.length()
		rich_editor.selection_start = cursor_pos - placeholder.length() - end_mark.length()
		rich_editor.selection_end = cursor_pos - end_mark.length()

func add_button_hover_effect(button: Button):
	if not button:
		return
	
	# Create a visible hover background
	var hover_style = StyleBoxFlat.new()
	hover_style.bg_color = Color(0.3, 0.3, 0.3, 0.8)  # Dark gray with transparency
	hover_style.corner_radius_top_left = 3
	hover_style.corner_radius_top_right = 3
	hover_style.corner_radius_bottom_left = 3
	hover_style.corner_radius_bottom_right = 3
	
	button.add_theme_stylebox_override("hover", hover_style)

func add_transparent_normal_style(button: Button):
	if not button:
		return
	
	# Create transparent normal state
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0, 0, 0, 0)  # Completely transparent
	normal_style.border_width_left = 0
	normal_style.border_width_right = 0
	normal_style.border_width_top = 0
	normal_style.border_width_bottom = 0
	
	button.add_theme_stylebox_override("normal", normal_style)

func insert_text(text: String):
	if not rich_editor:
		return
	
	# Insert text at current cursor position
	var cursor_pos = rich_editor.cursor_position
	var current_text = rich_editor.get_text()
	var new_text = current_text.insert(cursor_pos, text)
	rich_editor.set_text(new_text)
	rich_editor.cursor_position = cursor_pos + text.length()
	
	# Manually trigger save since set_text() doesn't emit text_changed signal
	call_deferred("save_notes")

func toggle_formatting_legacy(format_type: String):
	# LEGACY: Rich text formatting approach
	if not rich_editor:
		return
	
	# Toggle the specific formatting type
	match format_type:
		"bold":
			rich_editor.toggle_formatting_type("bold")
		"italic":
			rich_editor.toggle_formatting_type("italic")
		"strikethrough":
			rich_editor.toggle_formatting_type("strikethrough")
		"code":
			rich_editor.toggle_formatting_type("code")

func _clear_all():
	if rich_editor:
		rich_editor.save_state()  # Save state before clearing
		rich_editor.set_text("")
		save_notes()

func _on_text_changed():
	call_deferred("save_notes")
	match current_mode:
		1: # Render mode
			call_deferred("update_render_display")

func save_notes():
	if not rich_editor:
		return
	
	var content = rich_editor.get_text()
	
	# Auto-create README.md on first note (when content is not empty)
	if not FileAccess.file_exists(SAVE_PATH) and content.strip_edges() != "":
		print("Auto-creating README.md with first note")
	
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(content)
		file.close()
	else:
		print("ERROR: Could not open ", SAVE_PATH, " for writing")

func load_notes():
	if not FileAccess.file_exists(SAVE_PATH):
		# README.md doesn't exist - will be auto-created on first note
		if rich_editor:
			rich_editor.set_text("")
		last_modified_time = 0
		return
		
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file:
		var content = file.get_as_text()
		last_modified_time = FileAccess.get_modified_time(SAVE_PATH)
		file.close()
		
		if rich_editor:
			rich_editor.set_text(content)
			match current_mode:
				1: # Render mode
					call_deferred("update_render_display")

func setup_file_monitoring():
	# Create timer for file monitoring
	file_monitor_timer = Timer.new()
	file_monitor_timer.timeout.connect(_check_file_changes)
	file_monitor_timer.wait_time = 1.0  # Check every second
	file_monitor_timer.autostart = true
	add_child(file_monitor_timer)

func _check_file_changes():
	if not FileAccess.file_exists(SAVE_PATH):
		return
	
	var current_modified_time = FileAccess.get_modified_time(SAVE_PATH)
	if current_modified_time > last_modified_time:
		# File was modified externally - reload it
		print("README.md was modified externally, reloading...")
		load_notes_without_losing_cursor()

func load_notes_without_losing_cursor():
	# Save current cursor position
	var cursor_pos = 0
	var selection_start = -1
	var selection_end = -1
	
	if rich_editor:
		cursor_pos = rich_editor.cursor_position
		selection_start = rich_editor.selection_start
		selection_end = rich_editor.selection_end
	
	# Load new content
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file:
		var content = file.get_as_text()
		last_modified_time = FileAccess.get_modified_time(SAVE_PATH)
		file.close()
		
		if rich_editor:
			# Update content without triggering save
			rich_editor.set_text(content)
			
			# Restore cursor position (clamped to new content length)
			var max_pos = rich_editor.get_total_text_length()
			rich_editor.cursor_position = clamp(cursor_pos, 0, max_pos)
			
			# Restore selection if it was valid
			if selection_start != -1 and selection_end != -1:
				rich_editor.selection_start = clamp(selection_start, 0, max_pos)
				rich_editor.selection_end = clamp(selection_end, 0, max_pos)
			
			rich_editor.queue_redraw()
			match current_mode:
				1: # Render mode
					call_deferred("update_render_display")

func setup_markdown_heading_menu():
	if not heading_btn:
		return
	var popup = heading_btn.get_popup()
	popup.clear()  # Clear any existing items
	popup.add_item("# H1", 1)
	popup.add_item("## H2", 2)
	popup.add_item("### H3", 3)
	popup.add_item("#### H4", 4)
	popup.add_item("##### H5", 5)
	popup.add_item("###### H6", 6)
	popup.id_pressed.connect(_on_markdown_heading_selected)

func setup_heading_menu():
	if not heading_btn:
		return
	var popup = heading_btn.get_popup()
	popup.add_item("H1", 0)
	popup.add_item("H2", 1)
	popup.add_item("H3", 2)
	popup.add_item("H4", 3)
	popup.add_item("H5", 4)
	popup.add_item("H6", 5)
	popup.id_pressed.connect(_on_heading_selected)

func setup_markdown_list_menu():
	if not list_btn:
		return
	var popup = list_btn.get_popup()
	popup.clear()  # Clear any existing items
	popup.add_item("- Bullet List", 0)
	popup.add_item("1. Numbered List", 1)
	popup.add_item("- [ ] Checklist", 2)
	popup.id_pressed.connect(_on_markdown_list_selected)

func setup_list_menu():
	if not list_btn:
		return
	var popup = list_btn.get_popup()
	popup.add_item("• Bullet List", 0)
	popup.add_item("1. Numbered List", 1)
	popup.add_item("☐ Checklist", 2)
	popup.id_pressed.connect(_on_list_selected)

func _on_markdown_heading_selected(id: int):
	if not rich_editor or current_mode == 1:  # Don't format in render mode
		return
	
	# Insert markdown heading syntax
	var heading_markers = ["", "#", "##", "###", "####", "#####", "######"]
	if id >= 1 and id <= 6:
		insert_line_start_formatting(heading_markers[id] + " ")

func _on_heading_selected(id: int):
	if not rich_editor:
		return
	var heading_level = id + 1
	rich_editor.insert_heading(heading_level)

func _on_markdown_list_selected(id: int):
	if not rich_editor or current_mode == 1:  # Don't format in render mode
		return
	
	match id:
		0: # Bullet list
			insert_line_start_formatting("- ")
		1: # Numbered list
			insert_line_start_formatting("1. ")
		2: # Checklist
			insert_line_start_formatting("- [ ] ")

func insert_line_start_formatting(prefix: String):
	if not rich_editor:
		return
	
	# Get current cursor position and find start of line
	var cursor_pos = rich_editor.cursor_position
	var text = rich_editor.get_text()
	var line_start = cursor_pos
	
	# Find the start of current line
	while line_start > 0 and text[line_start - 1] != '\n':
		line_start -= 1
	
	# Insert prefix at start of line
	var new_text = text.insert(line_start, prefix)
	rich_editor.set_text(new_text)
	rich_editor.cursor_position = cursor_pos + prefix.length()

func _on_list_selected(id: int):
	if not rich_editor:
		return
	match id:
		0: # Bullet list
			rich_editor.insert_list_item("bullet")
		1: # Numbered list
			rich_editor.insert_list_item("numbered")
		2: # Checklist
			rich_editor.insert_list_item("checklist")

func _insert_markdown_blockquote():
	if current_mode == 1:  # Don't format in render mode
		return
	insert_line_start_formatting("> ")

func _insert_markdown_code_block():
	if current_mode == 1:  # Don't format in render mode
		return
	var code_block = "```\ncode here\n```\n"
	insert_text(code_block)
	# Move cursor to select "code here"
	var cursor_pos = rich_editor.cursor_position
	rich_editor.cursor_position = cursor_pos - code_block.length() + 4  # After "```\n"
	rich_editor.selection_start = cursor_pos - code_block.length() + 4
	rich_editor.selection_end = cursor_pos - 4  # Before "\n```"

func _insert_markdown_horizontal_rule():
	if current_mode == 1:  # Don't format in render mode
		return
	insert_text("\n---\n")

func _insert_markdown_link():
	if current_mode == 1:  # Don't format in render mode
		return
	if rich_editor.has_selection():
		var selected_text = rich_editor.get_selected_text()
		var link_text = "[" + selected_text + "](url)"
		rich_editor.delete_selection()
		insert_text(link_text)
		# Select "url" part for easy editing
		var cursor_pos = rich_editor.cursor_position
		rich_editor.selection_start = cursor_pos - 4  # Start of "url)"
		rich_editor.selection_end = cursor_pos - 1   # End of "url"
	else:
		var link_text = "[text](url)"
		insert_text(link_text)
		# Select "text" part for easy editing
		var cursor_pos = rich_editor.cursor_position
		rich_editor.selection_start = cursor_pos - link_text.length() + 1  # After "["
		rich_editor.selection_end = cursor_pos - 6  # Before "]"

func _insert_markdown_image():
	if current_mode == 1:  # Don't format in render mode
		return
	var image_text = "![alt text](image_url)"
	insert_text(image_text)
	# Select "alt text" for easy editing
	var cursor_pos = rich_editor.cursor_position
	rich_editor.selection_start = cursor_pos - image_text.length() + 2  # After "!["
	rich_editor.selection_end = cursor_pos - 13  # Before "]"

func _insert_markdown_table():
	if current_mode == 1:  # Don't format in render mode
		return
	var table_text = """| Header 1 | Header 2 | Header 3 |
|----------|----------|----------|
| Cell 1   | Cell 2   | Cell 3   |
| Cell 4   | Cell 5   | Cell 6   |

"""
	insert_text(table_text)

# Legacy functions
func _insert_blockquote():
	if rich_editor:
		rich_editor.insert_blockquote()

func _insert_code_block():
	if rich_editor:
		rich_editor.insert_code_block()

func _insert_horizontal_rule():
	if rich_editor:
		rich_editor.insert_horizontal_rule()

func _insert_link():
	if rich_editor:
		rich_editor.insert_link()

func _insert_image():
	if rich_editor:
		rich_editor.insert_image()

func _insert_table():
	if rich_editor:
		rich_editor.insert_table()

# Two-mode functions
func _toggle_mode():
	current_mode = (current_mode + 1) % 2
	set_mode(current_mode)

func set_mode(mode: int):
	current_mode = mode
	
	# Hide all displays first
	rich_editor.visible = false
	render_display.visible = false
	
	match current_mode:
		0: # Source mode
			rich_editor.visible = true
			if mode_toggle_btn:
				mode_toggle_btn.text = "👁"
				mode_toggle_btn.tooltip_text = "Switch to Render Mode"
		1: # Render mode
			render_display.visible = true
			update_render_display()
			if mode_toggle_btn:
				mode_toggle_btn.text = "✏️"
				mode_toggle_btn.tooltip_text = "Switch to Source Mode"

func update_render_display():
	if not render_display or not rich_editor:
		return
	
	var markdown_text = rich_editor.get_text()
	var bbcode_text = markdown_to_bbcode(markdown_text)
	render_display.text = bbcode_text

func create_mixed_content_display(bbcode_text: String):
	# Create custom container if it doesn't exist
	if not custom_render_container:
		custom_render_container = VBoxContainer.new()
		custom_render_container.name = "CustomRenderContainer"
		custom_render_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		custom_render_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		render_display.get_parent().add_child(custom_render_container)
		# Position it in the same place as render_display
		custom_render_container.position = render_display.position
		custom_render_container.size = render_display.size
	
	# Clear existing content
	for child in custom_render_container.get_children():
		child.queue_free()
	
	# Hide regular render display and show custom container
	render_display.visible = false
	custom_render_container.visible = true
	
	# Split content by image markers and create mixed layout
	var parts = bbcode_text.split("<<<IMAGE:")
	
	# Add first text part (before any images)
	if parts.size() > 0 and parts[0].strip_edges() != "":
		add_text_block(parts[0])
	
	# Process remaining parts (each starts with image info)
	for i in range(1, parts.size()):
		var part = parts[i]
		var marker_end = part.find(">>>")
		if marker_end != -1:
			var image_info = part.substr(0, marker_end)
			var remaining_text = part.substr(marker_end + 3)
			
			# Parse image info: "path:alt_text"
			var info_parts = image_info.split(":", 2)
			if info_parts.size() >= 2:
				var image_path = info_parts[0]
				var alt_text = info_parts[1]
				add_image_block(image_path, alt_text)
			
			# Add remaining text after image
			if remaining_text.strip_edges() != "":
				add_text_block(remaining_text)

func add_text_block(bbcode_text: String):
	var label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.text = bbcode_text
	label.fit_content = true
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_render_container.add_child(label)

func add_image_block(image_path: String, alt_text: String):
	var texture = load_image_texture(image_path)
	if texture:
		var texture_rect = TextureRect.new()
		texture_rect.texture = texture
		texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		texture_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		custom_render_container.add_child(texture_rect)

func clear_image_overlays():
	# Remove all existing image overlay controls
	for overlay in image_overlays:
		if is_instance_valid(overlay):
			overlay.queue_free()
	image_overlays.clear()
	created_overlays.clear()  # Reset the tracking dictionary

func update_render_text_only():
	# Update just the text content without recreating image overlays
	if not render_display or not rich_editor:
		return
	
	var markdown_text = rich_editor.get_text()
	var bbcode_text = markdown_to_bbcode(markdown_text)
	render_display.text = bbcode_text


func markdown_to_bbcode(markdown: String) -> String:
	var bbcode = markdown
	
	# Process line by line for easier regex handling
	var lines = bbcode.split("\n")
	var processed_lines = []
	
	for line in lines:
		var processed_line = line
		
		# Headers (process first)
		if line.begins_with("######"):
			processed_line = "[font_size=14][b]" + line.substr(6).strip_edges() + "[/b][/font_size]"
		elif line.begins_with("#####"):
			processed_line = "[font_size=16][b]" + line.substr(5).strip_edges() + "[/b][/font_size]"
		elif line.begins_with("####"):
			processed_line = "[font_size=18][b]" + line.substr(4).strip_edges() + "[/b][/font_size]"
		elif line.begins_with("###"):
			processed_line = "[font_size=20][b]" + line.substr(3).strip_edges() + "[/b][/font_size]"
		elif line.begins_with("##"):
			processed_line = "[font_size=24][b]" + line.substr(2).strip_edges() + "[/b][/font_size]"
		elif line.begins_with("#"):
			processed_line = "[font_size=28][b]" + line.substr(1).strip_edges() + "[/b][/font_size]"
		
		# Blockquotes
		elif line.begins_with("> "):
			processed_line = "[i]> " + line.substr(2) + "[/i]"
		
		# Lists
		elif line.begins_with("- [ ] "):
			processed_line = "☐ " + line.substr(6)
		elif line.begins_with("- [x] "):
			processed_line = "☑ " + line.substr(6)
		elif line.begins_with("- "):
			processed_line = "• " + line.substr(2)
		elif line.length() > 3 and line[0].is_valid_int() and line.find(". ") > 0:
			var regex = RegEx.new()
			regex.compile("^([0-9]+)\\. (.*)")
			var result = regex.search(line)
			if result:
				processed_line = result.get_string(1) + ". " + result.get_string(2)
		
		# Horizontal rules
		elif line.begins_with("---"):
			processed_line = "─────────────────────"
		
		processed_lines.append(processed_line)
	
	bbcode = "\n".join(processed_lines)
	
	# Inline formatting (process globally)
	var regex: RegEx
	
	# Bold **text**
	regex = RegEx.new()
	regex.compile("\\*\\*([^*]+)\\*\\*")
	bbcode = regex.sub(bbcode, "[b]$1[/b]", true)
	
	# Italic *text*
	regex = RegEx.new()
	regex.compile("\\*([^*]+)\\*")
	bbcode = regex.sub(bbcode, "[i]$1[/i]", true)
	
	# Strikethrough ~~text~~
	regex = RegEx.new()
	regex.compile("~~([^~]+)~~")
	bbcode = regex.sub(bbcode, "[s]$1[/s]", true)
	
	# Code blocks ```text``` - process FIRST to avoid conflicts with inline code
	# Clean pattern to avoid extra highlighted spaces
	regex = RegEx.new()
	regex.compile("```\\s*\\n([\\s\\S]*?)\\n\\s*```")
	bbcode = regex.sub(bbcode, "[bgcolor=#0d1117][color=#e6edf3]$1[/color][/bgcolor]", true)
	
	# Inline code `text` - process after code blocks
	regex = RegEx.new()
	regex.compile("`([^`]+)`")
	bbcode = regex.sub(bbcode, "[bgcolor=#1a1a1a][color=#f0f0f0] $1 [/color][/bgcolor]", true)
	
	# Images ![alt](src) - process before links to avoid conflicts
	regex = RegEx.new()
	regex.compile("!\\[([^\\]]*)\\]\\(([^)]+)\\)")
	var matches = regex.search_all(bbcode)
	for match in matches:
		var alt_text = match.get_string(1)
		var image_src = match.get_string(2)
		var image_bbcode = process_image(image_src, alt_text)
		bbcode = bbcode.replace(match.get_string(0), image_bbcode)
	
	# Links [text](url)
	regex = RegEx.new()
	regex.compile("\\[([^\\]]+)\\]\\(([^)]+)\\)")
	bbcode = regex.sub(bbcode, "[url=$2]$1[/url]", true)
	
	return bbcode

func process_image(image_src: String, alt_text: String) -> String:
	if image_src.begins_with("http://") or image_src.begins_with("https://"):
		# For remote images, check if cached and load, otherwise download
		return process_remote_image(image_src, alt_text)
	else:
		# For local images, try to load directly
		return process_local_image(image_src, alt_text)

func process_remote_image(url: String, alt_text: String) -> String:
	# Create cache path
	var cache_dir = "user://image_cache/"
	if not DirAccess.dir_exists_absolute(cache_dir):
		DirAccess.open("user://").make_dir_recursive("image_cache")
	
	var url_hash = url.hash()
	var file_extension = ".jpg"  # Default
	if url.get_extension() in ["jpg", "jpeg", "png", "gif", "bmp", "webp"]:
		file_extension = "." + url.get_extension()
	
	var cached_file_path = cache_dir + str(url_hash) + file_extension
	var image_key = "img_" + str(url_hash)
	
	# Check if image is cached
	if FileAccess.file_exists(cached_file_path):
		# Load image and create a texture resource that can be referenced
		var texture = load_image_texture(cached_file_path)
		if texture:
			# Store texture in a resource file that BBCode can reference
			var temp_resource_path = "user://temp_img_" + str(url_hash) + ".tres"
			ResourceSaver.save(texture, temp_resource_path)
			return "[img]" + temp_resource_path + "[/img]"
		else:
			return "[color=red]Failed to load: " + alt_text + "[/color]"
	else:
		# Download and show loading placeholder
		download_image_with_callback(url, cached_file_path, alt_text, url_hash)  
		return "[color=#6a6a6a]Loading: " + alt_text + "...[/color]"

func process_local_image(image_src: String, alt_text: String) -> String:
	# For now, just show a simple placeholder for local images to avoid res:// errors
	return "[color=#6a9955]📁 Local Image: " + alt_text + "[/color]"

func register_image_with_rtl(image_path: String, alt_text: String, hash_id: int) -> String:
	# Check if we've already registered this image
	var image_key = "img_" + str(hash_id)
	
	# Load and resize the image
	var texture = load_image_texture(image_path)
	if not texture:
		return "\n[color=red]Failed to load: " + alt_text + "[/color]\n"
	
	# Register the image with RichTextLabel during processing
	if render_display:
		# Add the resized image with correct parameters for Godot 4
		render_display.add_image(texture, 0, 0, Color.WHITE, INLINE_ALIGNMENT_CENTER, Rect2(), image_key)
		
		# Return BBCode to display the image inline at this exact position
		return "[img=" + image_key + "]"
	
	return "[color=red]Failed to load: " + alt_text + "[/color]"

func download_and_cache_image_simple(url: String, alt_text: String):
	# Simple download without image registration - just for caching
	var cache_dir = "user://image_cache/"
	if not DirAccess.dir_exists_absolute(cache_dir):
		DirAccess.open("user://").make_dir_recursive("image_cache")
	
	var url_hash = url.hash()
	var file_extension = ".png"
	if url.get_extension() in ["jpg", "jpeg", "png", "gif", "bmp", "webp"]:
		file_extension = "." + url.get_extension()
	
	var cached_file_path = cache_dir + str(url_hash) + file_extension
	
	if not FileAccess.file_exists(cached_file_path):
		download_image_async_simple(url, cached_file_path, alt_text)

func download_image_async_simple(url: String, cache_path: String, alt_text: String):
	var http_request = HTTPRequest.new()
	add_child(http_request)
	
	var callable = func(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
		http_request.queue_free()
		if response_code == 200 and body.size() > 0:
			var file = FileAccess.open(cache_path, FileAccess.WRITE)
			if file:
				file.store_buffer(body)
				file.close()
				print("Downloaded and cached image: ", alt_text)
	
	http_request.request_completed.connect(callable)
	http_request.request(url)

func download_and_cache_image_sync(url: String, alt_text: String) -> String:
	# Create a cache directory for downloaded images
	var cache_dir = "user://image_cache/"
	if not DirAccess.dir_exists_absolute(cache_dir):
		DirAccess.open("user://").make_dir_recursive("image_cache")
	
	# Generate a filename from the URL hash
	var url_hash = url.hash()
	var file_extension = ".png"  # Default extension
	if url.get_extension() in ["jpg", "jpeg", "png", "gif", "bmp", "webp"]:
		file_extension = "." + url.get_extension()
	
	var cached_file_path = cache_dir + str(url_hash) + file_extension
	
	# Check if image is already cached
	if FileAccess.file_exists(cached_file_path):
		# Try to load the cached image
		return try_load_cached_image(cached_file_path, alt_text, url_hash)
	else:
		# If not cached, start async download and return placeholder
		download_image_async(url, cached_file_path, alt_text, url_hash)
		return "[color=#4a9eff][🔄 Loading: " + alt_text + "...][/color]"

func try_load_local_image(file_path: String, alt_text: String) -> String:
	print("DEBUG: try_load_local_image called with file_path='", file_path, "' alt='", alt_text, "'")
	
	# Validate the file path first
	if file_path == "" or file_path == "res://":
		print("DEBUG: Empty or invalid file_path detected: '", file_path, "'")
		return "[color=red][❌ Empty image path: " + alt_text + "][/color]"
	
	# For imported resources (res:// paths), verify the file exists first
	if file_path.begins_with("res://"):
		print("DEBUG: Checking if resource exists: ", file_path)
		if ResourceLoader.exists(file_path):
			print("DEBUG: Resource exists, returning BBCode")
			return "[img]" + file_path + "[/img]"
		else:
			print("DEBUG: Resource does not exist")
			return "[color=red][❌ Resource not found: " + alt_text + " (" + file_path + ")][/color]"
	else:
		# For non-imported files, show info
		print("DEBUG: Non-res:// path, showing placeholder")
		return "[color=#6a9955][📁 Local Image: " + alt_text + " (" + file_path + ")][/color]"

func try_load_cached_image(file_path: String, alt_text: String, url_hash: int) -> String:
	var image_key = "cached_img_" + str(url_hash)
	
	# Load the image data and create an ImageTexture
	var image = Image.new()
	var error = load_image_from_file(image, file_path)
	
	if error == OK:
		# Create texture and register it with RichTextLabel
		var texture = ImageTexture.new()
		texture.set_image(image)
		
		# Add the texture with a unique key
		if render_display:
			print("DEBUG: Registering image: ", image_key)
			render_display.add_image(texture, 400, 0, Color.WHITE, INLINE_ALIGNMENT_CENTER, Rect2(), image_key)
			return "[img=" + image_key + "][/img]"
	
	# If loading failed, show error
	return "[color=red][❌ Failed to load: " + alt_text + "][/color]"

func load_image_from_file(image: Image, file_path: String) -> int:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return ERR_FILE_CANT_OPEN
	
	var file_data = file.get_buffer(file.get_length())
	file.close()
	
	# Try different image formats based on extension
	var ext = file_path.get_extension().to_lower()
	match ext:
		"jpg", "jpeg":
			return image.load_jpg_from_buffer(file_data)
		"png":
			return image.load_png_from_buffer(file_data)
		"webp":
			return image.load_webp_from_buffer(file_data)
		_:
			# Try PNG first, then JPG
			var error = image.load_png_from_buffer(file_data)
			if error != OK:
				error = image.load_jpg_from_buffer(file_data)
			return error

func download_image_async(url: String, cache_path: String, alt_text: String, url_hash: int):
	# Create an HTTP request
	var http_request = HTTPRequest.new()
	add_child(http_request)
	
	# Set up the completion handler
	var callable = func(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
		http_request.queue_free()
		
		if response_code == 200 and body.size() > 0:
			# Save the image to cache
			var file = FileAccess.open(cache_path, FileAccess.WRITE)
			if file:
				file.store_buffer(body)
				file.close()
				print("Downloaded and cached image: ", alt_text)
				
				# Load the image and add it to RichTextLabel
				var image = Image.new()
				var error = load_image_from_file(image, cache_path)
				if error == OK:
					var texture = ImageTexture.new()
					texture.set_image(image)
					var image_key = "cached_img_" + str(url_hash)
					if render_display:
						render_display.add_image(texture, 400, 0, Color.WHITE, INLINE_ALIGNMENT_CENTER, Rect2(), image_key)
				
				# Refresh the render to show the downloaded image
				call_deferred("update_render_display")
		else:
			print("Failed to download image from: ", url, " (Code: ", response_code, ")")
	
	http_request.request_completed.connect(callable)
	
	# Start the download
	http_request.request(url)


# Formatting functions that work in both modes
func _apply_bold_formatting():
	match current_mode:
		0: # Source mode
			insert_markdown_formatting("**")
		1: # Render mode (display only - do nothing)
			return

func _apply_italic_formatting():
	match current_mode:
		0: # Source mode
			insert_markdown_formatting("*")
		1: # Render mode (display only - do nothing)
			return


func _apply_strikethrough_formatting():
	match current_mode:
		0: # Source mode
			insert_markdown_formatting("~~")
		1: # Render mode (display only - do nothing)
			return

func _apply_code_formatting():
	match current_mode:
		0: # Source mode
			insert_markdown_formatting("`")
		1: # Render mode (display only - do nothing)
			return

# Context menu for render display
func setup_render_context_menu():
	render_context_menu = PopupMenu.new()
	render_context_menu.name = "RenderContextMenu"
	add_child(render_context_menu)
	
	# Add copy option
	render_context_menu.add_item("Copy", 0)
	render_context_menu.add_item("Select All", 1)
	
	# Connect menu signals
	render_context_menu.id_pressed.connect(_on_render_context_menu_selected)
	
	# Connect right-click on render display
	render_display.gui_input.connect(_on_render_display_input)

func _on_render_display_input(event: InputEvent):
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			# Show context menu at mouse position
			render_context_menu.position = get_global_mouse_position()
			render_context_menu.popup()

func _on_render_context_menu_selected(id: int):
	match id:
		0: # Copy
			_copy_render_selection()
		1: # Select All
			_select_all_render()

func _copy_render_selection():
	if render_display.get_selected_text() != "":
		DisplayServer.clipboard_set(render_display.get_selected_text())

func _select_all_render():
	render_display.select_all()

func _on_link_clicked(meta):
	# Open URL in the default system browser
	OS.shell_open(str(meta))

func create_image_overlay(image_path: String, alt_text: String, hash_id: int):
	if not render_display or not render_display.visible:
		return
	
	# Check if we've already created an overlay for this image
	var overlay_key = str(hash_id)
	if created_overlays.has(overlay_key):
		print("Overlay already exists for: ", alt_text)
		return
	
	# Load the image texture
	var texture = load_image_texture(image_path)
	if not texture:
		print("Failed to create texture from: ", image_path)
		return
	
	# Mark this overlay as created
	created_overlays[overlay_key] = true
	
	# Create TextureRect overlay
	var texture_rect = TextureRect.new()
	texture_rect.texture = texture
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	
	# Calculate size maintaining aspect ratio with 200px max width
	var img_size = texture.get_size()
	var max_width = 200
	var display_width = min(max_width, img_size.x)
	var display_height = int(display_width * img_size.y / img_size.x)
	
	print("Setting image size to: ", Vector2(display_width, display_height))
	
	# Force the size in multiple ways
	texture_rect.size = Vector2(display_width, display_height)
	texture_rect.custom_minimum_size = Vector2(display_width, display_height)
	texture_rect.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	
	# Prevent it from expanding beyond our size
	texture_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	texture_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	
	# Position the image
	texture_rect.position = Vector2(10, 50 + image_overlays.size() * (display_height + 10))
	
	# Add to render display parent
	render_display.get_parent().add_child(texture_rect)
	image_overlays.append(texture_rect)
	
	print("Created image overlay for: ", alt_text)

func load_image_texture(file_path: String) -> Texture2D:
	# Try to load as resource first (for res:// paths)
	if file_path.begins_with("res://") and ResourceLoader.exists(file_path):
		var texture = load(file_path)
		return resize_texture_if_needed(texture)
	
	# For cached files, load manually
	var image = Image.new()
	var error = load_image_from_file(image, file_path)
	
	if error == OK:
		# Resize the image to our desired max width before creating texture
		var original_size = image.get_size()
		var max_width = 200
		if original_size.x > max_width:
			var new_height = int(max_width * original_size.y / original_size.x)
			image.resize(max_width, new_height, Image.INTERPOLATE_LANCZOS)
			print("Resized image from ", original_size, " to ", image.get_size())
		
		var texture = ImageTexture.new()
		texture.set_image(image)
		return texture
	
	return null

func resize_texture_if_needed(texture: Texture2D) -> Texture2D:
	if not texture:
		return null
	
	var original_size = texture.get_size()
	var max_width = 200
	
	if original_size.x <= max_width:
		return texture
	
	# Need to resize - convert to image, resize, then back to texture
	var image = texture.get_image()
	var new_height = int(max_width * original_size.y / original_size.x)
	image.resize(max_width, new_height, Image.INTERPOLATE_LANCZOS)
	
	var new_texture = ImageTexture.new()
	new_texture.set_image(image)
	print("Resized texture from ", original_size, " to ", image.get_size())
	return new_texture

func download_image_with_callback(url: String, cache_path: String, alt_text: String, url_hash: int):
	var http_request = HTTPRequest.new()
	add_child(http_request)
	
	var callable = func(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
		http_request.queue_free()
		if response_code == 200 and body.size() > 0:
			var file = FileAccess.open(cache_path, FileAccess.WRITE)
			if file:
				file.store_buffer(body)
				file.close()
				print("Downloaded: ", alt_text)
				# Save the image as a resource file so BBCode can reference it
				var texture = load_image_texture(cache_path)
				if texture:
					var temp_resource_path = "user://temp_img_" + str(url_hash) + ".tres"
					ResourceSaver.save(texture, temp_resource_path)
				# Refresh the entire display to replace loading text with image
				call_deferred("update_render_display")
	
	http_request.request_completed.connect(callable)
	http_request.request(url)