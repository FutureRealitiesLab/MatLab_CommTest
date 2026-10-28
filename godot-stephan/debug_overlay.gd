extends Label
## Zeigt Netzwerk- und Darstellungsstatistiken an (F3 schaltet um).

@export var receiver_path: NodePath
@export var view_path: NodePath


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		visible = not visible


func _process(_delta: float) -> void:
	var r := get_node_or_null(receiver_path)
	var v := get_node_or_null(view_path)
	if r == null or v == null:
		text = "Empfaenger oder Ansicht nicht gefunden"
		return
	var lines: Array[String] = [
		"Render-FPS:    %d" % Engine.get_frames_per_second(),
		"UDP-Port:      %d (%s)" % [r.port, "lauscht" if r.listening else "FEHLER"],
		"Absender:      %s" % r.last_sender,
		"Pakete/s:      %.0f" % r.packets_per_s,
		"Frames/s:      %.1f   Warteschlange: %d" % [r.frames_per_s, r.queue_size],
		"Frame-Groesse: %.1f KB   Datenrate: %.0f KB/s" % [r.kb_per_frame, r.kb_per_s],
		"Verworfen:     %d   Ungueltig: %d" % [r.dropped_frames, r.bad_packets],
		"Session:       %d" % r.session_id,
		"Magic:         %s   Frame: %d" % [r.last_magic, r.last_frame_id],
		"Ebenen:        %s" % ", ".join(v.layers.keys()),
		"Colormap:      %s (C wechselt)" % v.colormap_name(),
	]
	text = "\n".join(lines)
