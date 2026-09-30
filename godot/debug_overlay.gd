extends Label
## Zeigt Netzwerk- und Render-Statistiken des UDP-Empfaengers an.

@export var receiver_path: NodePath


func _process(_delta: float) -> void:
	var r := get_node_or_null(receiver_path)
	if r == null:
		text = "Empfaenger nicht gefunden"
		return
	text = "\n".join([
		"Render-FPS:     %d" % Engine.get_frames_per_second(),
		"UDP-Port:       %d (%s)" % [r.port, "lauscht" if r.listening else "FEHLER"],
		"Absender:       %s" % r.last_sender,
		"Pakete/s:       %.0f" % r.packets_per_s,
		"Volumen/s:      %.1f" % r.frames_per_s,
		"Frame-Groesse:  %.1f KB" % r.kb_per_frame,
		"Datenrate:      %.0f KB/s" % r.kb_per_s,
		"Verworfen:      %d" % r.dropped_frames,
		"Grid:           %d^3" % r._grid,
		"Ungueltig:      %d" % r.bad_packets,
		"Letztes Paket:  %d Byte" % r.last_pkt_size,
		"Header:         %s" % r.last_hdr,
		"Frame/Chunks:   %d  %d/%d" % [r._frame_id, r._chunks_got, r._chunk_count],
	])
