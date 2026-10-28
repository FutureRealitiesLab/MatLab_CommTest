extends SceneTree
## Temporaerer Live-Test: empfaengt echte udpSend-Pakete und zeichnet sie.

var _scene: Node
var _seen := {}
var _time := 0.0
var _max_pps := 0.0


func _initialize() -> void:
	_scene = load("res://main.tscn").instantiate()
	_scene.get_node("Receiver").port = 4343
	root.add_child(_scene)
	_scene.get_node("Receiver").frame_received.connect(
			func(magic: String, info: Dictionary, payload: PackedByteArray) -> void:
				_seen[magic] = [info.dims, payload.size()])


func _process(delta: float) -> bool:
	_time += delta
	var r: Node = _scene.get_node("Receiver")
	_max_pps = maxf(_max_pps, r.packets_per_s)
	if _time > 45.0:
		var keys := _seen.keys()
		keys.sort()
		for k in keys:
			print(k, " ", _seen[k])
		print("magics: ", keys.size(), " layers: ", _scene.get_node("View").layers.keys())
		print("max pps ", _max_pps, " sender ", r.last_sender, " bad ", r.bad_packets,
				" dropped ", r.dropped_frames, " session ", r.session_id, " listening ", r.listening)
		quit(0)
	return false
