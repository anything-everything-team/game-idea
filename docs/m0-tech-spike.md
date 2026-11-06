# M0 — Tech spike

**Goal (from [GAME_DESIGN.md §16](../GAME_DESIGN.md#16-roadmap)):** prove that blocky voxel terrain performs well enough on both targets before building the game on top of it.

**Exit criteria**
- [ ] Chunked terrain with greedy meshing streams around a walking player at a smooth 60 fps on desktop
- [ ] Acceptable frame rate in the browser (web build, single-threaded)
- [ ] Web export hosted and playable
- [ ] Decide chunk size (16³ vs 32³) and whether meshing stays in GDScript or moves to a compiled extension

## What's in the spike

| Piece | File | Notes |
|---|---|---|
| Platform presets | `scripts/core/platform_preset.gd` | Desktop: 512×512×256 zone, 12-chunk view radius, shadows. Web: 256×256×128, 6-chunk radius, no shadows. |
| Terrain generator | `scripts/voxel/terrain_generator.gd` | Deterministic from the seed: hills, ridged mountains, snow, sand lowlands, caves, ore, glowing alien plants. |
| Greedy mesher | `scripts/voxel/chunk_mesher.gd` | Merges same-type faces into large quads. Pure function, runs on worker threads. |
| Chunk builder | `scripts/voxel/chunk_builder.gd` | Generate + mesh a whole column as one resumable job. |
| World streamer | `scripts/world/voxel_world.gd` | Loads nearest columns first; worker threads on desktop, per-frame time budget on web. Edits remesh instantly. |
| Player | `scripts/player/player.gd` | Walk, sprint, jump, jetpack, creative fly, 1st/3rd person, break/place blocks. Voxel AABB collision (no physics meshes). |
| Look | `shaders/voxel.gdshader` | Flat colors, darkened block edges, tiny per-block tint, emissive blocks. Works in both renderers. |
| HUD | `scripts/ui/hud.gd` | Live FPS, chunk counts, triangles, generate/mesh timings, spawn and full-load times. |

## Running it

1. Install [Godot 4.7](https://godotengine.org/download) (standard build, not .NET).
2. Open the repository folder as a project and press **Play** (F5).

### Controls

| Key | Action |
|---|---|
| Click | Capture the mouse |
| WASD / arrows | Move |
| Shift | Sprint (boost while flying) |
| Space | Jump; hold in the air for jetpack |
| Mouse | Look |
| Left / right click | Break / place block |
| 1–7, mouse wheel | Select block (hull, light, stone, dirt, grass, sand, ore) |
| V | Toggle first / third person |
| F | Toggle fly mode (Space up, C down) |
| N | New landing zone (random seed) |
| H | Hide help |
| Esc | Release the mouse |

### Command-line options

Pass these after `--`, e.g. `godot --path . -- --preset=web --threads=off`.

| Option | Effect |
|---|---|
| `--seed=N` | Landing zone seed (default 1337) |
| `--preset=web` / `--preset=desktop` | Force a platform's limits |
| `--threads=off` | Single-threaded chunk building, like the web build |
| `--benchmark` | Fly across the zone automatically, print stats every second, then quit |
| `--bench-seconds=N` | Benchmark length (default 30) |

Headless benchmark (measures CPU-side generation and meshing without a GPU):

```bash
godot --headless --path . -- --benchmark
godot --headless --path . -- --benchmark --preset=web --threads=off
```

## Exporting

Install the Godot 4.7 export templates (Editor → Manage Export Templates), then:

```bash
GODOT=/path/to/godot tools/export.sh   # writes build/web, build/linux, build/windows
python3 tools/serve_web.py              # play the web build at http://127.0.0.1:8060/
```

The web preset is **single-threaded** so it runs on any static host (itch.io, GitHub Pages) without special server headers.

## Results

_To be filled in from benchmark runs and play-testing on real hardware._

| Target | Spawn ready | Full view loaded | Avg / min FPS | Generate (ms/column) | Mesh (ms/chunk) |
|---|---|---|---|---|---|
| Desktop, threaded | | | | | |
| Desktop, `--threads=off` | | | | | |
| Web (browser) | | | | | |

## Decisions to make at the end of M0

- **Chunk size:** keep 16³ unless meshing overhead per chunk dominates.
- **Meshing language:** if web mesh time per chunk is too high for smooth streaming, move `chunk_mesher.gd` and `terrain_generator.gd` to a GDExtension (C++ or Rust) and keep gameplay in GDScript.
- **Collision approach:** the voxel AABB sweep is enough on foot; ships (M3) will need their own approach.
