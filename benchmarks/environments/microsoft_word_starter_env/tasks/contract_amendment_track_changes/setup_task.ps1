# Setup script for contract_amendment_track_changes task.
# CLEAN -> RECORD -> SEED -> LAUNCH ordering strictly followed.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$logPath = "C:\Users\Docker\task_pre_task_contract_amendment_track_changes.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up contract_amendment_track_changes task ==="

    # Load shared helpers
    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) {
        throw "Missing task utils: $utils"
    }
    . $utils

    # Close any open Word windows
    Get-Process WINWORD -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # CLEAN: Remove stale output files
    $destDir = "C:\Users\Docker\Desktop\WordTasks"
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null

    $staleFiles = @(
        "$destDir\patent_license_final.docx",
        "$destDir\patent_license_draft_tracked.docx",
        "C:\Users\Docker\contract_amendment_track_changes_result.json"
    )
    foreach ($f in $staleFiles) {
        if (Test-Path $f) {
            Remove-Item $f -Force
            Write-Host "Removed stale file: $f"
        }
    }

    # RECORD: Save task start timestamp
    $taskStartUnix = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $timestampFile = "C:\Users\Docker\task_start_contract_amendment_track_changes.txt"
    $taskStartUnix | Out-File -FilePath $timestampFile -Encoding ASCII -Force
    Write-Host "Task start timestamp: $taskStartUnix"

    # SEED: Copy data file to Desktop
    $srcFile = "C:\workspace\data\patent_license_draft_tracked.docx"
    if (-not (Test-Path $srcFile)) {
        throw "Source data file not found: $srcFile"
    }
    $destFile = "$destDir\patent_license_draft_tracked.docx"
    Copy-Item $srcFile -Destination $destFile -Force
    Write-Host "Data file seeded at: $destFile"

    # LAUNCH: Open the document in Word interactively
    $wordExe = Find-WordExe
    Write-Host "Word executable: $wordExe"
    Launch-WordDocumentInteractive -WordExe $wordExe -DocumentPath $destFile -WaitSeconds 14

    # Best-effort dialog dismissal
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

    Write-Host "=== contract_amendment_track_changes task setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
