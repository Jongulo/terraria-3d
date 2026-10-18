#!/bin/sh
# Opens the placeable picker: choose how each placeable block is shown in 3D
# (saves game/data/placeables.json).
cd "$(dirname "$0")"
exec godot --path game res://editor/placeable_picker.tscn "$@"
