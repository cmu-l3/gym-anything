# Setup script for create_business_letter task.
# Opens Word with a blank document.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_create_business_letter.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up create_business_letter task ==="

    # Load shared helpers
    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) {
        throw "Missing task utils: $utils"
    }
    . $utils

    # Close any open Word windows
    Get-Process WINWORD -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Ensure WordTasks directory exists
    $destDir = "C:\Users\Docker\Desktop\WordTasks"
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null

    # Find Word and launch with blank document
    $wordExe = Find-WordExe
    Write-Host "Word executable: $wordExe"
    Write-Host "Launching Word via scheduled task (interactive desktop)..."
    Launch-WordDocumentInteractive -WordExe $wordExe -WaitSeconds 12

    # Best-effort: dismiss common first-run dialogs
    Write-Host "Dismissing dialogs via PyAutoGUI server..."
    try {
        Dismiss-WordDialogsBestEffort
        Write-Host "Dialog dismissal complete."
    } catch {
        Write-Host "WARNING: Dialog dismissal failed: $($_.Exception.Message)"
    }

    # Verify Word is running
    $wordProc = Get-Process WINWORD -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($wordProc) {
        Write-Host "Word is running (PID: $($wordProc.Id))"
    } else {
        Write-Host "WARNING: Word process not found after launch."
    }

    Write-Host "=== create_business_letter task setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
