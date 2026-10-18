#!/bin/sh
# Opens the NPC picker: choose how each enemy, boss and town NPC is shown in 3D
# (saves game/data/npc_models.json).
cd "$(dirname "$0")"
exec godot --path game res://editor/npc_picker.tscn "$@"
