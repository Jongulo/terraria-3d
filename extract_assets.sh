#!/bin/sh
# Extracts assets from a local Terraria install into game/assets/terraria (not committed).
set -e
cd "$(dirname "$0")"
TERRARIA=${1:-"$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/common/Terraria"}
OUT=game/assets/terraria
cargo build --release --manifest-path tools/xnb-extract/Cargo.toml
tools/xnb-extract/target/release/xnb-extract "$TERRARIA/Content" "$OUT"
python3 -I tools/terraria_ids.py "$TERRARIA/Terraria.exe" "$OUT/ids.json"
python3 -I tools/terraria_recipes.py "$TERRARIA/Terraria.exe" "$OUT/ids.json" "$OUT/recipes.json"
python3 -I tools/terraria_shimmer.py "$TERRARIA/Terraria.exe" "$OUT/ids.json" "$OUT/shimmer.json"
python3 -I tools/terraria_dust.py "$TERRARIA/Terraria.exe" game/data/blocks.json "$OUT/tile_dust.json"
python3 -I tools/terraria_gore.py "$TERRARIA/Terraria.exe" game/data/npcs.json "$OUT/ids.json" "$OUT/npc_gore.json"
# Godot loads these at runtime; keep the editor from importing ~16k files.
touch "$OUT/.gdignore"
