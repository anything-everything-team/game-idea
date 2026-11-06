#!/usr/bin/env bash
# Export the web and desktop builds into build/.
# Requires Godot 4.7 and its export templates. Point GODOT at the editor binary:
#   GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64 tools/export.sh
set -euo pipefail

GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."

mkdir -p build/web build/linux build/windows

# Make sure the import cache (.godot/) exists before exporting.
"$GODOT" --headless --import

"$GODOT" --headless --export-release "Web" build/web/index.html
"$GODOT" --headless --export-release "Linux" build/linux/starwright.x86_64
"$GODOT" --headless --export-release "Windows Desktop" build/windows/starwright.exe

echo "Builds written to build/. Serve the web build with: python3 tools/serve_web.py"
