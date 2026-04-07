# dismiss_dialogs.ps1 — Dismiss Lobby Track startup dialogs via PyAutoGUI TCP server.
# Called from task_utils.ps1 Dismiss-LobbyTrackDialogs and from setup_lobbytrack.ps1 warm-up.
#
# Lobby Track Free Edition shows two dialogs on every launch:
#   1. "Lobby Track Classification" (FREE Edition info) → Click "Continue" button at (641, 401)
#   2. "Configure Workstation" wizard → Uncheck "Show at startup" (391, 523), then close X (884, 184)

$ErrorActionPreference = "Continue"

function Send-DismissPyAutoGUI([string]$json) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $ar = $client.BeginConnect("127.0.0.1", 5555, $null, $null)
        $waited = $ar.AsyncWaitHandle.WaitOne(3000, $false)
        if (-not $waited -or -not $client.Connected) {
            $client.Close()
            return $null
        }
        $client.EndConnect($ar)
        $stream = $client.GetStream()
        $stream.ReadTimeout = 10000
        $stream.WriteTimeout = 5000
        $writer = New-Object System.IO.StreamWriter($stream)
        $writer.AutoFlush = $true
        $writer.WriteLine($json)
        $reader = New-Object System.IO.StreamReader($stream)
        $line = $reader.ReadLine()
        $client.Close()
        return $line
    } catch {
        try { $client.Close() } catch { }
        return $null
    }
}

function DismissClick([int]$x, [int]$y, [string]$desc = "") {
    $resp = Send-DismissPyAutoGUI "{`"action`":`"click`",`"x`":$x,`"y`":$y}"
    if ($desc) { Write-Host "  $desc -> $resp" }
}

function DismissPress([string]$key, [string]$desc = "") {
    $resp = Send-DismissPyAutoGUI "{`"action`":`"press`",`"key`":`"$key`"}"
    if ($desc) { Write-Host "  $desc -> $resp" }
}

# Phase 0: Language Selection dialog — press Enter to accept English default
Write-Host "Dismiss phase 0: Language selection dialog..."
Start-Sleep -Seconds 2
DismissPress "enter" "Accept language (Enter)"
Start-Sleep -Seconds 5

# Phase 1: FREE Edition Classification dialog — click "Continue" button
Write-Host "Dismiss phase 1: FREE Edition Classification dialog..."
DismissClick 641 401 "Continue button"
Start-Sleep -Seconds 3

# Phase 2: Configure Workstation dialog — uncheck "Show at startup" and close
Write-Host "Dismiss phase 2: Configure Workstation dialog..."
DismissClick 391 523 "Uncheck Show at startup"
Start-Sleep -Seconds 1
DismissClick 884 184 "Close Configure dialog (X)"
Start-Sleep -Seconds 2

# Phase 3: Any remaining dialogs — generic dismiss
Write-Host "Dismiss phase 3: Remaining dialogs..."
DismissPress "escape" "Escape"
Start-Sleep -Seconds 1
DismissPress "enter" "Enter"
Start-Sleep -Seconds 1
DismissPress "escape" "Escape"
Start-Sleep -Seconds 1

# Phase 4: Close any browser windows opened by the website link
Write-Host "Dismiss phase 4: Close stray browser..."
DismissPress "escape" "Escape browser"
Start-Sleep -Seconds 1

Write-Host "Dialog dismissal complete"
