# Builds the Rust voxel core and installs it into the Godot project (Windows).
#   .\build.ps1            release build
#   .\build.ps1 debug      debug build
param([string]$BuildProfile = "release")
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
if ($BuildProfile -eq "release") {
	cargo build --release --manifest-path rust/voxel_core/Cargo.toml
} else {
	cargo build --manifest-path rust/voxel_core/Cargo.toml
}
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
New-Item -ItemType Directory -Force game/bin | Out-Null
Copy-Item "rust/voxel_core/target/$BuildProfile/voxel_core.dll" game/bin/voxel_core.dll -Force
Write-Host "installed game/bin/voxel_core.dll ($BuildProfile)"
