## Registers input actions in code so the project file stays readable.
## Physical keycodes keep WASD in the same place on non-QWERTY layouts.
## Note: Ctrl is deliberately unused — Ctrl+W closes the browser tab on web.
extends RefCounted

const KEYS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_SPACE],
	"sprint": [KEY_SHIFT],
	"descend": [KEY_C],
	"toggle_camera": [KEY_V],
	"toggle_fly": [KEY_F],
	"toggle_help": [KEY_H],
	"new_seed": [KEY_N],
}


static func register() -> void:
	for action in KEYS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for keycode in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			InputMap.action_add_event(action, ev)
