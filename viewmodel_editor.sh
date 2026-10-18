#!/bin/sh
# Opens the first-person weapon pose editor (saves to game/data/viewmodel.json).
cd "$(dirname "$0")"
exec godot --path game res://editor/viewmodel_editor.tscn "$@"
