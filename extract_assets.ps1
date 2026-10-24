# Extracts assets from a local Terraria install into game/assets/terraria (not committed). Windows.
#   .\extract_assets.ps1                    finds Terraria in your Steam libraries
#   .\extract_assets.ps1 D:\path\to\Terraria
param([string]$Terraria = "")
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

if (-not $Terraria) {
	$steam = (Get-ItemProperty HKCU:\Software\Valve\Steam -ErrorAction SilentlyContinue).SteamPath
	if (-not $steam) { $steam = "${env:ProgramFiles(x86)}\Steam" }
	$libs = @($steam)
	$vdf = Join-Path $steam "steamapps\libraryfolders.vdf"
	if (Test-Path $vdf) {
		$libs += Select-String -Path $vdf -Pattern '"path"\s+"(.+)"' |
			ForEach-Object { $_.Matches[0].Groups[1].Value -replace '\\\\', '\' }
	}
	foreach ($l in $libs) {
		$t = Join-Path $l "steamapps\common\Terraria"
		if (Test-Path "$t\Terraria.exe") { $Terraria = $t; break }
	}
	if (-not $Terraria) { throw "Terraria not found in Steam libraries; pass its folder as an argument" }
}
Write-Host "Terraria: $Terraria"

$py = if (Get-Command py -ErrorAction SilentlyContinue) { "py" } else { "python" }
$out = "game/assets/terraria"
$exe = "$Terraria\Terraria.exe"

function Check { if ($LASTEXITCODE -ne 0) { throw "step failed ($LASTEXITCODE)" } }
cargo build --release --manifest-path tools/xnb-extract/Cargo.toml; Check
tools/xnb-extract/target/release/xnb-extract.exe "$Terraria\Content" $out; Check
& $py -I tools/terraria_ids.py $exe "$out/ids.json"; Check
& $py -I tools/terraria_recipes.py $exe "$out/ids.json" "$out/recipes.json"; Check
& $py -I tools/terraria_dust.py $exe game/data/blocks.json "$out/tile_dust.json"; Check
& $py -I tools/terraria_gore.py $exe game/data/npcs.json "$out/ids.json" "$out/npc_gore.json"; Check
# Godot loads these at runtime; keep the editor from importing ~16k files.
New-Item -ItemType File -Force "$out/.gdignore" | Out-Null
