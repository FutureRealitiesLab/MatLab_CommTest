extends Label
## Zeigt Netzwerk- und Render-Statistiken des UDP-Empfaengers an.

@export var receiver_path: NodePath


func _process(_delta: float) -> void:
	var r := get_node_or_null(receiver_path)
	if r == null:
		text = "Empfaenger nicht gefunden"
		return
	var lines: Array[String] = [
		"Render-FPS:     %d" % Engine.get_frames_per_second(),
		"UDP-Port:       %d (%s)" % [r.port, "lauscht" if r.listening else "FEHLER"],
		"Absender:       %s" % r.last_sender,
		"Pakete/s:       %.0f" % r.packets_per_s,
		"Volumen/s:      %.1f" % r.frames_per_s,
		"Frame-Groesse:  %.1f KB" % r.kb_per_frame,
		"Datenrate:      %.0f KB/s" % r.kb_per_s,
		"Verworfen:      %d  Ungueltig: %d  Fremd: %d" % [r.dropped_frames, r.bad_packets, r.ignored_packets],
		"Grid:           %d x %d x %d (%s)" % [r._dims.x, r._dims.y, r._dims.z,
				"2D Hoehenkarte" if r._dims.z == 1 else "3D Volumen"],
		"Wertebereich:   %.3g .. %.3g" % [r.data_min, r.data_max],
		"Colormap:       %s   Interpolation: %s" % [r.colormap_name, "an" if r.interpolate else "aus"],
	]
	if r.title != "":
		lines.append("Titel:          %s" % r.title)
	text = "\n".join(lines)
