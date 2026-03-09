# Setup script for sox_walkthrough_narrative task.
# CLEAN -> RECORD -> SEED -> LAUNCH ordering strictly followed.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$logPath = "C:\Users\Docker\task_pre_task_sox_walkthrough_narrative.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up sox_walkthrough_narrative task ==="

    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) { throw "Missing task utils: $utils" }
    . $utils

    Get-Process WINWORD -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # CLEAN
    $destDir = "C:\Users\Docker\Desktop\WordTasks"
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null

    $staleFiles = @(
        "$destDir\ap_walkthrough_final.docx",
        "$destDir\ap_walkthrough_raw.docx",
        "C:\Users\Docker\sox_walkthrough_narrative_result.json"
    )
    foreach ($f in $staleFiles) {
        if (Test-Path $f) { Remove-Item $f -Force; Write-Host "Removed: $f" }
    }

    # RECORD
    $taskStartUnix = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $taskStartUnix | Out-File -FilePath "C:\Users\Docker\task_start_sox_walkthrough_narrative.txt" -Encoding ASCII -Force
    Write-Host "Task start timestamp: $taskStartUnix"

    # SEED
    $srcFile = "C:\workspace\data\ap_walkthrough_raw.docx"
    if (-not (Test-Path $srcFile)) { throw "Source data file not found: $srcFile" }
    $destFile = "$destDir\ap_walkthrough_raw.docx"
    Copy-Item $srcFile -Destination $destFile -Force
    Write-Host "Data file seeded at: $destFile"

    # LAUNCH
    $wordExe = Find-WordExe
    Launch-WordDocumentInteractive -WordExe $wordExe -DocumentPath $destFile -WaitSeconds 14

    try {
        Dismiss-WordDialogsBestEffort
    } catch {
        Write-Host "WARNING: Dialog dismissal failed: $($_.Exception.Message)"
    }

    $wordProc = Get-Process WINWORD -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($wordProc) {
        Write-Host "Word is running (PID: $($wordProc.Id))"
    } else {
        Write-Host "WARNING: Word process not found after launch."
    }

    Write-Host "=== sox_walkthrough_narrative task setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
