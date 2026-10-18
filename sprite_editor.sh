#!/bin/sh
# Opens the sprite editor: choose how the tree canopy, trunk and cactus sprites are
# upscaled, warped and noised (saves game/data/sprite_fx.json).
cd "$(dirname "$0")"
exec godot --path game res://editor/sprite_editor.tscn "$@"
