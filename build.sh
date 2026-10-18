#!/bin/sh
# Builds the Rust voxel core and installs it into the Godot project.
set -e
cd "$(dirname "$0")"
PROFILE=${1:-release}
if [ "$PROFILE" = release ]; then
	cargo build --release --manifest-path rust/voxel_core/Cargo.toml
else
	cargo build --manifest-path rust/voxel_core/Cargo.toml
fi
mkdir -p game/bin
cp "rust/voxel_core/target/$PROFILE/libvoxel_core.so" game/bin/libvoxel_core.so
echo "installed game/bin/libvoxel_core.so ($PROFILE)"
