#!/bin/sh
# Opens the model sculptor: hand-tune voxel models for the "tuned" method of
# the NPC and placeable pickers (saves game/data/tuned/).
cd "$(dirname "$0")"
exec godot --path game res://editor/model_sculptor.tscn "$@"
