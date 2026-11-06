## Debug HUD for the tech spike: performance numbers, hotbar, help, loading state.
extends CanvasLayer

const Blocks = preload("res://scripts/voxel/blocks.gd")
const VoxelWorld = preload("res://scripts/world/voxel_world.gd")
const Player = preload("res://scripts/player/player.gd")
const PlatformPreset = preload("res://scripts/core/platform_preset.gd")

const HELP := """WASD move · Shift sprint · Space jump / jetpack
Mouse look · LMB break · RMB place
1-7 / wheel select block
V 1st / 3rd person · F fly (Space up, C down)
N new landing zone · H hide help · Esc release mouse"""

var world: VoxelWorld
var player: Player
var renderer := ""

var stats_label: Label
var help_label: Label
var hotbar_label: Label
var center_label: Label
var crosshair: Label
var refresh := 0.0


func _ready() -> void:
	renderer = PlatformPreset.renderer_name()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var small := LabelSettings.new()
	small.font_size = 14
	small.outline_size = 4
	small.outline_color = Color(0, 0, 0, 0.85)
	var big := LabelSettings.new()
	big.font_size = 26
	big.outline_size = 6
	big.outline_color = Color(0, 0, 0, 0.85)

	stats_label = _label(root, small)
	stats_label.position = Vector2(12, 10)

	help_label = _label(root, small)
	help_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	help_label.offset_left = 12
	help_label.offset_right = -12
	help_label.offset_top = 10
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	help_label.text = HELP

	hotbar_label = _label(root, small)
	hotbar_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hotbar_label.offset_top = -44
	hotbar_label.offset_bottom = -16
	hotbar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	crosshair = _label(root, big)
	crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crosshair.text = "+"

	center_label = _label(root, big)
	center_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	center_label.offset_top = 90
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _label(parent: Control, settings: LabelSettings) -> Label:
	var l := Label.new()
	l.label_settings = settings
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _unhandled_input(event) -> void:
	if event is InputEventKey and event.is_action_pressed("toggle_help"):
		help_label.visible = not help_label.visible


func _process(delta: float) -> void:
	crosshair.visible = not player.frozen
	if player.frozen:
		center_label.text = "Generating landing zone…"
	elif Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		center_label.text = "Click to play"
	else:
		center_label.text = ""

	var parts := PackedStringArray()
	for i in Player.PLACEABLE.size():
		var block_name: String = Blocks.NAMES[Player.PLACEABLE[i]]
		var entry := "%d %s" % [i + 1, block_name]
		parts.append("[ %s ]" % entry if i == player.slot else entry)
	hotbar_label.text = "   ".join(parts)

	refresh -= delta
	if refresh <= 0.0:
		refresh = 0.25
		stats_label.text = _stats_text()


func _stats_text() -> String:
	var s := world.stats()
	var p := player.position
	var lines := PackedStringArray()
	lines.append("Starwright M0 tech spike — %s preset · %s · threads: %s" % [
		world.preset["name"], renderer, str(world.thread_count) if world.thread_count > 0 else "off"])
	lines.append("FPS %d   process %.1f ms" % [
		Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0])
	lines.append("Zone %d×%d×%d blocks · seed %d · view radius %d chunks" % [
		world.size_xz, world.size_xz, world.height_blocks, world.world_seed, world.view_radius])
	lines.append("Columns loaded %d · pending %d · building %d" % [
		s["columns_loaded"], s["pending"], s["in_flight"]])
	lines.append("Chunk meshes %d · stored %d · triangles %s" % [
		s["chunks_meshed"], s["chunks_stored"], _thousands(s["tris"])])
	lines.append("Generate %.2f ms/column · mesh %.2f ms/column (%.2f ms/chunk) · last edit %.2f ms" % [
		s["gen_ms_per_column"], s["mesh_ms_per_column"], s["mesh_ms_per_chunk"], s["last_edit_ms"]])
	lines.append("Spawn ready %s · full view loaded %s" % [_secs(s["spawn_ms"]), _secs(s["full_load_ms"])])
	lines.append("Pos %.1f, %.1f, %.1f · %s · %s camera · jetpack %d%%" % [
		p.x, p.y, p.z, "flying" if player.fly else "walking",
		"3rd" if player.third_person else "1st", int(player.jet_fuel * 100.0)])
	return "\n".join(lines)


static func _secs(ms: float) -> String:
	return "…" if ms < 0.0 else "%.1f s" % (ms / 1000.0)


static func _thousands(n: int) -> String:
	if n >= 1000000:
		return "%.2fM" % (n / 1000000.0)
	if n >= 1000:
		return "%.1fk" % (n / 1000.0)
	return str(n)
