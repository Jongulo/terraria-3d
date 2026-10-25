# Runs the test suites (Windows). Gameplay and editor tests run headless (no windows).
#   .\run_tests.ps1            Rust + headless Godot tests
#   .\run_tests.ps1 -Visual    also the screenshot tests (opens a window briefly)
# Godot is $env:GODOT if set, else godot on PATH; use the *_console.exe build so output is captured.
# Screenshots go to $env:SHOTS (default $env:TEMP\terraria3d-shots).
param([switch]$Visual)
Set-Location $PSScriptRoot
$Godot = if ($env:GODOT) { $env:GODOT } else { "godot" }
$Shots = if ($env:SHOTS) { $env:SHOTS } else { "$env:TEMP\terraria3d-shots" }
New-Item -ItemType Directory -Force $Shots | Out-Null
$script:Fail = 0

# Runs Godot with a timeout and returns its output lines; a hung run is killed.
function Invoke-Godot([string[]]$GodotArgs, [int]$Secs) {
	$out = [IO.Path]::GetTempFileName()
	$err = [IO.Path]::GetTempFileName()
	$quoted = $GodotArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }
	$p = Start-Process $Godot -ArgumentList $quoted -NoNewWindow -PassThru `
		-RedirectStandardOutput $out -RedirectStandardError $err
	if (-not $p.WaitForExit($Secs * 1000)) { taskkill /T /F /PID $p.Id | Out-Null; $p.WaitForExit() }
	$lines = @(Get-Content $out) + @(Get-Content $err)
	Remove-Item $out, $err -ErrorAction SilentlyContinue
	return $lines
}

# The Godot tests load game/bin/voxel_core.dll, so build and install it from
# this checkout first: a DLL left from an older build runs the old worldgen.
Write-Host "== Build"
& .\build.ps1 | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Host "build failed; not running tests"; exit 1 }

Write-Host "== Rust"
$rust = cargo test --release --manifest-path rust/voxel_core/Cargo.toml 2>&1 | ForEach-Object { "$_" }
$first = $rust | Select-String "test result" | Select-Object -First 1
if (-not $first -or "$first" -notmatch " 0 failed") { $script:Fail = 1 }
Write-Host $(if ($first) { "$first".Trim() } else { "no test result" })

Write-Host "== Script check"
# Compile every script (tests included) before running anything: a test that
# fails to parse would otherwise sit idle until its timeout.
Invoke-Godot @("--headless", "--path", "game", "--import") 300 | Out-Null
$check = Invoke-Godot @("--headless", "--audio-driver", "Dummy", "--path", "game", "res://tests/compile_check.tscn") 60
if (-not ($check | Select-String "COMPILE OK")) {
	$check | Select-String "SCRIPT ERROR|at: |COMPILE" | Select-Object -First 20 | ForEach-Object { Write-Host $_ }
	Write-Host "script errors; not running Godot tests"
	exit 1
}

function Run([string]$Name, [int]$Secs, [switch]$Headless) {
	$a = @("--audio-driver", "Dummy", "--path", "game")
	# Windowed runs also get a frame-count backstop (--quit-after) so a stuck window closes itself.
	if ($Headless) { $a += @("--headless", "--fixed-fps", "60") } else { $a += @("--quit-after", "$($Secs * 70)") }
	$a += @("res://tests/$Name.tscn", "--", $Shots)
	$out = Invoke-Godot $a $Secs
	$result = $out | Select-String "RESULT" | Select-Object -Last 1
	Write-Host "${Name}: $(if ($result) { "$result".Trim() } else { 'no result (crashed or timed out)' })"
	$out | Select-String "^FAIL|SCRIPT ERROR" | Select-Object -First 10 | ForEach-Object { Write-Host $_ }
	if ("$result" -notmatch "0 failures|ok") { $script:Fail = 1 }
	# A shader that doesn't compile draws with a fallback material and nothing
	# else complains, so it fails the run.
	if ($out | Select-String "SHADER ERROR") {
		Write-Host "${Name}: SHADER ERROR"
		$out | Select-String "SHADER ERROR" -Context 0, 3 | Select-Object -First 3 | ForEach-Object { Write-Host $_ }
		$script:Fail = 1
	}
}

Write-Host "== Godot (headless)"
Run game_test 240 -Headless
Run editor_test 90 -Headless
Run test_world_test 300 -Headless
Run test_world_kinds_test 120 -Headless
Run placeables_test 360 -Headless
Run sprite_editor_test 90 -Headless
Run npc_scale_editor_test 90 -Headless
Run npc_picker_test 120 -Headless
Run model_sculptor_test 180 -Headless
Run menu_world_test 60 -Headless
Run creative_test 120 -Headless

if ($Visual) {
	Write-Host "== Godot (visual, screenshots in $Shots)"
	Run render_test 180
	Run viewmodel_test 60
	Run menu_test 60
	Run waterfall_test 60
}
exit $script:Fail
