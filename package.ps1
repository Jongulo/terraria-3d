# Builds the Windows installer: dist\Terraria3D-Setup-<version>.exe (Windows).
#   .\package.ps1                  version 0.1.0
#   .\package.ps1 -Version 0.2.0
# Needs what build.ps1 needs, Godot ($env:GODOT if set, else godot on PATH) and Inno Setup 6
# (winget install JRSoftware.InnoSetup). Godot's export templates, an embeddable Python and
# ffmpeg are downloaded the first time (cached in dist\cache). No Terraria assets go in the
# installer: it extracts them from the player's own Terraria install (installer\extract.ps1).
param([string]$Version = "0.1.0")
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
Set-Location $PSScriptRoot
$Godot = if ($env:GODOT) { $env:GODOT } else { "godot" }
$PythonVersion = "3.12.10"
$dist = Join-Path $PSScriptRoot "dist"
$cache = Join-Path $dist "cache"
$stage = Join-Path $dist "stage"
New-Item -ItemType Directory -Force $cache | Out-Null
# Runs a program and fails on its exit code. (Windows PowerShell turns a program's stderr
# into errors when its output is redirected, which "Stop" would throw on.)
function Native([string]$Step, [scriptblock]$Run) {
	$ErrorActionPreference = "Continue"
	& $Run
	if ($LASTEXITCODE -ne 0) { throw "$Step failed ($LASTEXITCODE)" }
}

function Get-Cached([string]$Url, [string]$Name) {
	$file = Join-Path $cache $Name
	if (-not (Test-Path $file)) {
		Write-Host "downloading $Url"
		Invoke-WebRequest $Url -OutFile "$file.part"
		Move-Item "$file.part" $file
	}
	return $file
}

function Find-Iscc {
	if ($env:ISCC) { return $env:ISCC }
	$cmd = Get-Command ISCC.exe -ErrorAction SilentlyContinue
	if ($cmd) { return $cmd.Source }
	foreach ($p in "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
			"$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe") {
		if (Test-Path $p) { return $p }
	}
	throw "Inno Setup 6 not found: install it (winget install JRSoftware.InnoSetup) or set `$env:ISCC"
}
$iscc = Find-Iscc

Write-Host "== Rust"
Native "build.ps1" { ./build.ps1 }
Native "xnb-extract build" { cargo build --release --manifest-path tools/xnb-extract/Cargo.toml }

Write-Host "== Export templates"
# "4.7.2.stable.official.1a2b3c4" -> templates in export_templates\4.7.2.stable
$gv = (Native "godot --version" { & $Godot --version 2>$null } | Select-Object -Last 1).Trim()
if ($gv -notmatch '^(.+?\.stable)\.') { throw "package.ps1 needs a stable Godot build (this is $gv)" }
$tv = $Matches[1]
$templates = Join-Path $env:APPDATA "Godot\export_templates\$tv"
if (-not (Test-Path "$templates\windows_release_x86_64.exe")) {
	$tag = $tv -replace '\.stable$', '-stable'
	$tpz = Get-Cached "https://github.com/godotengine/godot/releases/download/$tag/Godot_v$tag`_export_templates.tpz" "templates-$tag.zip"
	$tmp = Join-Path $cache "templates-$tag"
	Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
	Expand-Archive $tpz $tmp
	New-Item -ItemType Directory -Force $templates | Out-Null
	Copy-Item "$tmp\templates\*" $templates -Recurse -Force
	Remove-Item -Recurse -Force $tmp
}
Write-Host "templates: $templates"

Write-Host "== Export"
Remove-Item -Recurse -Force (Join-Path $dist "game"), $stage -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force (Join-Path $dist "game") | Out-Null
$ErrorActionPreference = "Continue"
& $Godot --headless --path game --import 2>&1 | Out-Null
$ErrorActionPreference = "Stop"
Native "Godot export" { & $Godot --headless --path game --export-release "Windows Desktop" (Join-Path $dist "game\Terraria3D.exe") }
if (-not (Test-Path (Join-Path $dist "game\Terraria3D.exe"))) { throw "Godot export wrote no Terraria3D.exe" }

Write-Host "== Stage"
Copy-Item (Join-Path $dist "game") $stage -Recurse
$ex = Join-Path $stage "extract"
New-Item -ItemType Directory -Force "$ex\tools", "$ex\data", "$ex\licenses" | Out-Null
Copy-Item installer/extract.ps1 $ex
Copy-Item tools/xnb-extract/target/release/xnb-extract.exe $ex
foreach ($t in "terraria_ids", "terraria_recipes", "terraria_dust", "terraria_gore") { Copy-Item "tools/$t.py" "$ex\tools" }
Copy-Item game/data/blocks.json, game/data/npcs.json "$ex\data"
Copy-Item LICENSE (Join-Path $stage "LICENSE.txt")

$pyZip = Get-Cached "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-embed-amd64.zip" "python-$PythonVersion-embed-amd64.zip"
Expand-Archive $pyZip "$ex\python"
Copy-Item "$ex\python\LICENSE.txt" "$ex\licenses\python.txt"

# BtbN's "latest" release keeps only the newest few versions: use a cached build, else
# the newest LGPL one ($env:FFMPEG_ZIP names one instead, e.g. ffmpeg-n9.0-latest-win64-lgpl-9.0).
$FfmpegZip = $env:FFMPEG_ZIP
if (-not $FfmpegZip) {
	$cached = Get-ChildItem $cache -Filter "ffmpeg-n*-latest-win64-lgpl-*.zip" | Sort-Object Name | Select-Object -Last 1
	if ($cached) {
		$FfmpegZip = $cached.BaseName
	} else {
		$rel = Invoke-RestMethod "https://api.github.com/repos/BtbN/FFmpeg-Builds/releases/tags/latest"
		$FfmpegZip = $rel.assets.name | Where-Object { $_ -match '^ffmpeg-n[\d.]+-latest-win64-lgpl-[\d.]+\.zip$' } |
			Sort-Object { [version](($_ -replace '^ffmpeg-n([\d.]+)-.*', '$1') + ".0") } | Select-Object -Last 1
		if (-not $FfmpegZip) { throw "no LGPL win64 ffmpeg build in BtbN's latest release; set `$env:FFMPEG_ZIP" }
		$FfmpegZip = $FfmpegZip -replace '\.zip$', ''
	}
}
$ffZip = Get-Cached "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/$FfmpegZip.zip" "$FfmpegZip.zip"
$tmp = Join-Path $cache "ffmpeg"
Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
Expand-Archive $ffZip $tmp
Copy-Item "$tmp\$FfmpegZip\bin\ffmpeg.exe" $ex
Copy-Item "$tmp\$FfmpegZip\LICENSE.txt" "$ex\licenses\ffmpeg.txt"
Remove-Item -Recurse -Force $tmp
Set-Content "$ex\licenses\README.txt" @"
python\ is the embeddable CPython $PythonVersion from python.org (PSF License: python.txt).
ffmpeg.exe is an LGPL build of FFmpeg from https://github.com/BtbN/FFmpeg-Builds ($FfmpegZip;
LGPL: ffmpeg.txt); its source is at https://github.com/FFmpeg/FFmpeg.
"@

Write-Host "== Installer"
Native "ISCC" { & $iscc /Q "/DAppVersion=$Version" "/DStage=$stage" "/DOutDir=$dist" installer/terraria3d.iss }
Write-Host "built $(Join-Path $dist "Terraria3D-Setup-$Version.exe")"
