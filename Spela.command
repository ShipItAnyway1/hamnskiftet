#!/bin/bash
set -e
game_root="$(cd "$(dirname "$0")" && pwd)"
game_engine="${MOBILSPEL_GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
exec "$game_engine" --path "$game_root" --log-file "$game_root/game.log" "$@"
