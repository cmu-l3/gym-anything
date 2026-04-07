# Dismisses common ActivInspire first-run dialogs.
# Called from setup_activinspire.ps1 (warm-up) and task_utils.ps1 (per-task launch).
#
# ActivInspire v2.7 shows these dialogs on first launch:
#   1. Promethean License Agreement - checkbox "I accept" + "Run Personal Edition"
#   2. Welcome to ActivInspire - customization choice + "Continue"
#   3. ActivInspire Dashboard - "Close" button
#
# Coordinates are in 1280x720 screen space (matches VNC resolution).
# These were verified by visual grounding on actual screenshots.

$ErrorActionPreference = "Continue"

function Send-PyAutoGUI([string]$json) {
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect("127.0.0.1", 5555, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne(3000, $false)) {
            return "timeout"
        }
        $client.EndConnect($iar)
        $stream = $client.GetStream()
        $writer = New-Object System.IO.StreamWriter($stream)
        $writer.AutoFlush = $true
        $writer.WriteLine($json)
        $reader = New-Object System.IO.StreamReader($stream)
        $resp = $reader.ReadLine()
        $client.Close()
        return $resp
    } catch {
        return "error: $_"
    }
}

function Click-At([int]$x, [int]$y) {
    $json = "{`"action`":`"click`",`"x`":$x,`"y`":$y}"
    return (Send-PyAutoGUI $json)
}

function Press-Key([string]$key) {
    $json = "{`"action`":`"press`",`"keys`":`"$key`"}"
    return (Send-PyAutoGUI $json)
}

Write-Host "=== Dismissing ActivInspire dialogs ==="

# Phase 1: Promethean License Agreement
# - "I accept the terms of this license" checkbox at (472, 492)
# - "Run Personal Edition" button at (518, 518)
Write-Host "Phase 1: License Agreement..."
$result = Click-At 472 492
Write-Host "  Accept checkbox: $result"
Start-Sleep -Seconds 2
$result = Click-At 518 518
Write-Host "  Run Personal Edition: $result"
Start-Sleep -Seconds 5

# Phase 2: Welcome to ActivInspire (customization dialog)
# - "Continue" button at (756, 418)
Write-Host "Phase 2: Welcome dialog..."
$result = Click-At 756 418
Write-Host "  Continue: $result"
Start-Sleep -Seconds 5

# Phase 3: ActivInspire Dashboard
# - "Close" button at (843, 490)
Write-Host "Phase 3: Dashboard..."
$result = Click-At 843 490
Write-Host "  Close: $result"
Start-Sleep -Seconds 2

# Phase 4: ActivInspire Update dialog
# - "Cancel" button at approximately (808, 368)
Write-Host "Phase 4: Update dialog..."
$result = Click-At 808 368
Write-Host "  Cancel update: $result"
Start-Sleep -Seconds 2

# Phase 5: Generic fallback - press Escape for any stray dialogs
Write-Host "Phase 5: Generic dismissal..."
$result = Press-Key "escape"
Write-Host "  Escape: $result"
Start-Sleep -Seconds 1
$result = Press-Key "escape"
Write-Host "  Escape: $result"
Start-Sleep -Seconds 1

Write-Host "=== Dialog dismissal complete ==="
