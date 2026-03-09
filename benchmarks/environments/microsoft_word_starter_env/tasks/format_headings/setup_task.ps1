# Setup script for format_headings task.
# Opens the census press release document in Word.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_format_headings.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up format_headings task ==="

    # Load shared helpers
    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) {
        throw "Missing task utils: $utils"
    }
    . $utils

    # Close any open Word windows
    Get-Process WINWORD -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Ensure the data file exists on the Desktop
    $dataFile = "C:\Users\Docker\Desktop\WordTasks\census_press_release.docx"
    if (-not (Test-Path $dataFile)) {
        $destDir = "C:\Users\Docker\Desktop\WordTasks"
        New-Item -ItemType Directory -Force -Path $destDir | Out-Null
        Copy-Item "C:\workspace\data\census_press_release.docx" -Destination $dataFile -Force
    }
    Write-Host "Data file ready at: $dataFile"

    # Find Word and launch the document interactively
    $wordExe = Find-WordExe
    Write-Host "Word executable: $wordExe"
    Write-Host "Launching Word via scheduled task (interactive desktop)..."
    Launch-WordDocumentInteractive -WordExe $wordExe -DocumentPath $dataFile -WaitSeconds 12

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

    Write-Host "=== format_headings task setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
