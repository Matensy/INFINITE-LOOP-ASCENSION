#!/usr/bin/env bash
# Imports the project (refreshes the global class cache) and runs the
# headless test suite. Usage: tools/run_tests.sh [--filter=name]
set -euo pipefail
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . --script res://tests/run_tests.gd -- "$@"
