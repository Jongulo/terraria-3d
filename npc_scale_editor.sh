#!/bin/sh
# Opens the NPC scale editor: choose how big each enemy, boss and town NPC
# appears in the game (saves game/data/npc_scales.json).
cd "$(dirname "$0")"
exec godot --path game res://editor/npc_scale_editor.tscn "$@"
