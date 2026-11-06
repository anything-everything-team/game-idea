## Platform presets: one codebase, different limits for desktop and web.
## See GAME_DESIGN.md §11. The numbers here are the M0 starting points to measure.
##
## Command-line overrides (pass after `--`):
##   --preset=web | --preset=desktop   force a preset (e.g. profile web limits on desktop)
##   --threads=off                     force single-threaded chunk building (what the web build does)
extends RefCounted

const DESKTOP := {
	"name": "desktop",
	"zone_chunks_xz": 32,   # 32 * 16 = 512 x 512 blocks
	"zone_chunks_y": 16,    # 16 * 16 = 256 blocks tall
	"view_radius": 12,      # chunks
	"shadows": true,
	"frame_budget_ms": 6.0, # main-thread time per frame for chunk work
}

const WEB := {
	"name": "web",
	"zone_chunks_xz": 16,   # 256 x 256 blocks
	"zone_chunks_y": 8,     # 128 blocks tall
	"view_radius": 6,
	"shadows": false,
	"frame_budget_ms": 8.0,
}


static func current() -> Dictionary:
	var preset: Dictionary = (WEB if OS.has_feature("web") else DESKTOP).duplicate()
	var threads_available := not OS.has_feature("web") or OS.has_feature("threads")
	for arg in OS.get_cmdline_user_args():
		if arg == "--preset=web":
			preset = WEB.duplicate()
		elif arg == "--preset=desktop":
			preset = DESKTOP.duplicate()
		elif arg == "--threads=off":
			threads_available = false
	preset["threads"] = maxi(1, OS.get_processor_count() - 1) if threads_available else 0
	return preset


static func renderer_name() -> String:
	if RenderingServer.has_method("get_current_rendering_method"):
		return str(RenderingServer.call("get_current_rendering_method"))
	return str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "unknown"))
