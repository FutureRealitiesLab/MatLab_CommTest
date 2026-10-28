@tool
extends EditorPlugin

## plugin.gd – Registriert beim Aktivieren die Autoloads von Situs Core und
## aller vorhandenen Module sowie die Input-Actions.
##
## Module = Ordner unter modules/. Ordner löschen → Modul ist weg (kein Autoload).
## Modul vorhanden, aber nicht gewünscht → Project Setting
## "situs_core/modules/<modul_name>" auf false setzen.

const CORE_DIR := "res://addons/situs_core/"
const SitusSettings := preload("res://addons/situs_core/core/situs_settings.gd")

const CORE_AUTOLOADS := {
	"GameState":      CORE_DIR + "networking/game_state.gd",
	"NetworkManager": CORE_DIR + "networking/network_manager.gd",
	"SceneManager":   CORE_DIR + "core/scene_manager.gd",
}

## Modul-Ordner → Autoloads (Reihenfolge: nach den Core-Autoloads)
const MODULE_AUTOLOADS := {
	"modul_scene_loop": {
		"SceneLoop": CORE_DIR + "modules/modul_scene_loop/scene_loop.gd",
	},
}

const CORE_INPUTS := {
	"debug_toggle": KEY_TAB,
}

const MODULE_INPUTS := {
	"modul_scene_loop": {
		"scene_next":        KEY_N,
		"scene_loop_toggle": KEY_L,
	},
}

## Autoloads und Inputs landen in project.godot und bleiben dort (der Export braucht sie).
func _enter_tree() -> void:
	SitusSettings.register()
	for autoload_name in CORE_AUTOLOADS:
		_add_autoload(autoload_name, CORE_AUTOLOADS[autoload_name])
	_add_inputs(CORE_INPUTS)

	for module_name in MODULE_AUTOLOADS:
		if not _module_active(module_name):
			continue
		for autoload_name in MODULE_AUTOLOADS[module_name]:
			_add_autoload(autoload_name, MODULE_AUTOLOADS[module_name][autoload_name])
		_add_inputs(MODULE_INPUTS.get(module_name, {}))


func _module_active(module_name: String) -> bool:
	if not DirAccess.dir_exists_absolute(CORE_DIR + "modules/" + module_name):
		return false
	return ProjectSettings.get_setting("situs_core/modules/" + module_name, true)


func _add_autoload(autoload_name: String, path: String) -> void:
	if ProjectSettings.has_setting("autoload/" + autoload_name):
		return
	add_autoload_singleton(autoload_name, path)


func _add_inputs(actions: Dictionary) -> void:
	var changed := false
	for action_name in actions:
		var key: String = "input/" + str(action_name)
		if ProjectSettings.has_setting(key):
			continue
		var ev := InputEventKey.new()
		ev.physical_keycode = actions[action_name]
		ProjectSettings.set_setting(key, {"deadzone": 0.5, "events": [ev]})
		changed = true
	if changed:
		ProjectSettings.save()
