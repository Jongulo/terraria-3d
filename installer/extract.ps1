# Extracts assets from the user's own Terraria install for the installed game (the
# installer runs it; so does the Start menu's "Extract Terraria assets"). It lives in
# <game>\extract\ with xnb-extract.exe, ffmpeg.exe, an embedded Python, the tools and the
# data they read; assets go to <game>\assets\terraria\.
#   extract.ps1                      finds Terraria (Steam libraries, GOG)
#   extract.ps1 -Terraria D:\Games\Terraria
#   extract.ps1 -Find                prints the Terraria it would use (or nothing) and exits
param([string]$Terraria = "", [switch]$Find, [switch]$Pause)
$ErrorActionPreference = "Stop"
$here = $PSScriptRoot

function Find-Terraria {
	$dirs = @()
	$steam = (Get-ItemProperty HKCU:\Software\Valve\Steam -ErrorAction SilentlyContinue).SteamPath
	if (-not $steam) { $steam = "${env:ProgramFiles(x86)}\Steam" }
	$libs = @($steam)
	$vdf = Join-Path $steam "steamapps\libraryfolders.vdf"
	if (Test-Path $vdf) {
		$libs += Select-String -Path $vdf -Pattern '"path"\s+"(.+)"' |
			ForEach-Object { $_.Matches[0].Groups[1].Value -replace '\\\\', '\' }
	}
	$dirs += $libs | ForEach-Object { Join-Path $_ "steamapps\common\Terraria" }
	foreach ($k in "HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games\1207665503", "HKLM:\SOFTWARE\GOG.com\Games\1207665503") {
		$p = (Get-ItemProperty $k -ErrorAction SilentlyContinue).path
		if ($p) { $dirs += $p }
	}
	foreach ($d in $dirs) {
		if (Test-Path (Join-Path $d "Terraria.exe")) { return $d }
	}
	return ""
}

if ($Find) { Find-Terraria; exit 0 }

$game = Split-Path $here -Parent
$out = Join-Path $game "assets\terraria"
$log = Join-Path $here "extract.log"
Set-Content $log "" -Encoding UTF8
function Say([string]$Line) { Write-Host $Line; Add-Content $log $Line -Encoding UTF8 }

# Runs a step, its output to the console and the log.
function Step([string]$Name, [string]$Exe, [string[]]$StepArgs) {
	Say "== $Name"
	# (Windows PowerShell turns a native command's stderr into errors, which "Stop" would throw on.)
	$ErrorActionPreference = "Continue"
	& $Exe @StepArgs 2>&1 | ForEach-Object { Say "$_" }
	if ($LASTEXITCODE -ne 0) { throw "$Name failed (exit code $LASTEXITCODE)" }
}

$code = 0
try {
	if (-not $Terraria) { $Terraria = Find-Terraria }
	if (-not $Terraria -or -not (Test-Path (Join-Path $Terraria "Terraria.exe"))) {
		throw "Terraria not found. Install it (Steam or GOG), or run this with -Terraria <its folder>."
	}
	Say "Terraria: $Terraria"
	Say "Assets:   $out"
	# xnb-extract runs ffmpeg (bundled here) to encode the music.
	$env:PATH = "$here;$env:PATH"
	$py = Join-Path $here "python\python.exe"
	$exe = Join-Path $Terraria "Terraria.exe"
	Step "textures, sounds, music, fonts" "$here\xnb-extract.exe" @((Join-Path $Terraria "Content"), $out)
	Step "IDs and names" $py @("-I", "-X", "utf8", "$here\tools\terraria_ids.py", $exe, "$out\ids.json")
	Step "recipes" $py @("-I", "-X", "utf8", "$here\tools\terraria_recipes.py", $exe, "$out\ids.json", "$out\recipes.json")
	Step "shimmer" $py @("-I", "-X", "utf8", "$here\tools\terraria_shimmer.py", $exe, "$out\ids.json", "$out\shimmer.json")
	Step "tile dust" $py @("-I", "-X", "utf8", "$here\tools\terraria_dust.py", $exe, "$here\data\blocks.json", "$out\tile_dust.json")
	Step "NPC gore" $py @("-I", "-X", "utf8", "$here\tools\terraria_gore.py", $exe, "$here\data\npcs.json", "$out\ids.json", "$out\npc_gore.json")
	Say "Done."
} catch {
	Say "ERROR: $_"
	$code = 1
}
if ($Pause) { Read-Host "Press Enter to close" | Out-Null }
exit $code
