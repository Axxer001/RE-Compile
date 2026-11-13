<#
RE:Compile verification wrapper. Runs Godot suites, rejects anything short of an explicit PASS.

  powershell -NoProfile -ExecutionPolicy Bypass -File .\verify.ps1 -Suite All
  pwsh -NoProfile -File .\verify.ps1 -Suite Simulation

A suite passes only when: the process exits 0 within its timeout, prints exactly one
`RESULT {json}` line with status PASS, and no script/parse/resource error appears in its output.
Evidence (logs, captures, source hashes, summary.json) goes to evidence\<timestamp>\.
-Fixture fail|missing-pass|hang is forwarded to suites to prove the wrapper detects failure.
#>
param(
    [ValidateSet('Content', 'Simulation', 'Render', 'Mobile', 'Playthrough', 'Performance', 'All')]
    [string]$Suite = 'All',
    [ValidateSet('', 'fail', 'missing-pass', 'hang')]
    [string]$Fixture = '',
    [string]$Godot = '',
    [double]$TimeoutScale = 1.0
)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
if (-not $Godot) {
    foreach ($candidate in 'godot_console', 'godot') {
        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($cmd) { $Godot = $cmd.Source; break }
    }
}
if (-not $Godot) { Write-Error 'Godot executable not found; pass -Godot <path>.'; exit 2 }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$evidence = Join-Path $root "evidence\$stamp"
New-Item -ItemType Directory -Force $evidence | Out-Null
$errorPattern = 'SCRIPT ERROR|Parse Error|Failed to load|Cannot open file|Invalid call|^ERROR:|\bERROR: '

function Invoke-Stage([string]$name, [string[]]$arguments, [int]$timeoutSec, [bool]$expectResult) {
    $out = Join-Path $evidence "$name.out.log"
    $err = Join-Path $evidence "$name.err.log"
    $started = Get-Date
    $proc = Start-Process -FilePath $Godot -ArgumentList $arguments -WorkingDirectory $root `
        -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow -PassThru
    $null = $proc.Handle  # Windows PowerShell only reports ExitCode if the handle was opened
    $timedOut = -not $proc.WaitForExit([int]($timeoutSec * 1000 * $TimeoutScale))
    if ($timedOut) { try { $proc.Kill() } catch {} ; $proc.WaitForExit() }
    $text = ((Get-Content $out -Raw -ErrorAction SilentlyContinue) + "`n" + (Get-Content $err -Raw -ErrorAction SilentlyContinue))
    $reasons = @()
    $result = $null
    if ($timedOut) { $reasons += "timeout after $($timeoutSec * $TimeoutScale)s" }
    elseif ($proc.ExitCode -ne 0) { $reasons += "exit code $($proc.ExitCode)" }
    $errors = @($text -split "`r?`n" | Where-Object { $_ -match $errorPattern -and $_ -notmatch '^FAIL: ' })
    if ($errors.Count) { $reasons += "engine errors: " + ($errors | Select-Object -First 3) -join ' | ' }
    if ($expectResult) {
        $lines = @($text -split "`r?`n" | Where-Object { $_ -like 'RESULT {*' })
        if ($lines.Count -ne 1) { $reasons += "expected one RESULT line, found $($lines.Count)" }
        else {
            $result = $lines[0].Substring(7) | ConvertFrom-Json
            if ($result.status -ne 'PASS') { $reasons += "suite status $($result.status): " + ($result.failures -join '; ') }
        }
    }
    [pscustomobject]@{
        stage    = $name
        status   = $(if ($reasons.Count) { 'FAIL' } else { 'PASS' })
        reasons  = $reasons
        seconds  = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
        checks   = $(if ($result) { $result.checks } else { $null })
        captures = $(if ($result -and $result.captures) { $result.captures } else { @() })
        metrics  = $(if ($result -and $result.metrics) { $result.metrics } else { $null })
    }
}

$fixtureArgs = @()
if ($Fixture) { $fixtureArgs = @('--', "--fixture=$Fixture") }
$suites = @{
    Content     = { Invoke-Stage 'content' (@('--headless', '--path', '.', '-s', 'res://tools/validate_content.gd') + $fixtureArgs) 60 $true }
    Simulation  = { Invoke-Stage 'simulation' (@('--headless', '--path', '.', '-s', 'res://tests/simulation/run_simulation.gd') + $fixtureArgs) 60 $true }
    Render      = {
        $captureDir = Join-Path $evidence 'captures'
        New-Item -ItemType Directory -Force $captureDir | Out-Null
        $renderArgs = @('--path', '.', 'res://tests/render/baseline.tscn', '--', "--out=$captureDir")
        if ($Fixture) { $renderArgs += "--fixture=$Fixture" }
        Invoke-Stage 'render' $renderArgs 120 $true
    }
    Mobile      = {
        # Render suite again under the Mobile renderer (what Android uses).
        $captureDir = Join-Path $evidence 'captures-mobile'
        New-Item -ItemType Directory -Force $captureDir | Out-Null
        $mobileArgs = @('--rendering-method', 'mobile', '--path', '.', 'res://tests/render/baseline.tscn', '--', "--out=$captureDir")
        if ($Fixture) { $mobileArgs += "--fixture=$Fixture" }
        Invoke-Stage 'mobile' $mobileArgs 120 $true
    }
    # A bot plays a fresh run to LEVEL COMPLETE through the real loop; --fixed-fps runs it unthrottled.
    Playthrough = { Invoke-Stage 'playthrough' (@('--headless', '--fixed-fps', '60', '--path', '.', '-s', 'res://tests/playthrough/run_playthrough.gd') + $fixtureArgs) 180 $true }
    Performance = {
        # 3 s warm-up + 20 s sample plus startup.
        $captureDir = Join-Path $evidence 'captures'
        New-Item -ItemType Directory -Force $captureDir | Out-Null
        $perfArgs = @('--path', '.', 'res://tests/performance/stress.tscn', '--', "--out=$captureDir")
        if ($Fixture) { $perfArgs += "--fixture=$Fixture" }
        Invoke-Stage 'performance' $perfArgs 120 $true
    }
}
$order = if ($Suite -eq 'All') { 'Content', 'Simulation', 'Render', 'Mobile', 'Playthrough', 'Performance' } else { @($Suite) }

$results = @(Invoke-Stage 'import' @('--headless', '--path', '.', '--editor', '--quit') 120 $false)
if ($results[0].status -eq 'PASS') { foreach ($s in $order) { $results += & $suites[$s] } }

$sources = Get-ChildItem $root -Recurse -File -Include *.gd, *.tscn, *.tres, *.json, project.godot |
    Where-Object { $_.FullName -notmatch '\\(\.godot|evidence)\\' } |
    ForEach-Object { [pscustomobject]@{ path = $_.FullName.Substring($root.Length + 1); sha256 = (Get-FileHash $_.FullName -Algorithm SHA256).Hash } }
$overall = if (@($results | Where-Object status -ne 'PASS').Count) { 'FAIL' } else { 'PASS' }
[pscustomobject]@{
    suite = $Suite; fixture = $Fixture; status = $overall; timestamp = $stamp
    godot = (& $Godot --version 2>$null | Select-Object -Last 1); results = $results; sources = $sources
} | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $evidence 'summary.json') -Encoding UTF8

foreach ($r in $results) {
    $detail = if ($r.reasons) { ' - ' + ($r.reasons -join '; ') } elseif ($r.checks) { " ($($r.checks) checks)" } else { '' }
    Write-Host ("{0,-12} {1} {2,5}s{3}" -f $r.stage, $r.status, $r.seconds, $detail)
}
Write-Host "OVERALL $overall  evidence: $evidence"
exit $(if ($overall -eq 'PASS') { 0 } else { 1 })
