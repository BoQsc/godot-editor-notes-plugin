@tool
extends EditorPlugin

var dock

func _enter_tree():
	dock = preload("res://addons/editor_notes/notes_dock.tscn").instantiate()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)
	print("Editor Notes: Plugin enabled and Notes tab added to Inspector dock.")

func _exit_tree():
	remove_control_from_docks(dock)
	dock.free()
	print("Editor Notes: Plugin disabled and Notes tab removed from Inspector dock.")