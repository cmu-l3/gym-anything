# Export result for contract_amendment_track_changes task.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$logPath = "C:\Users\Docker\task_post_task_contract_amendment_track_changes.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Exporting contract_amendment_track_changes result ==="

    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) { throw "Missing task utils: $utils" }
    . $utils

    # Read task start timestamp
    $timestampFile = "C:\Users\Docker\task_start_contract_amendment_track_changes.txt"
    $taskStartUnix = 0
    if (Test-Path $timestampFile) {
        $taskStartUnix = [int](Get-Content $timestampFile -Raw).Trim()
    }
    Write-Host "Task start unix: $taskStartUnix"

    # Send Ctrl+S to save current document
    Write-Host "Sending Ctrl+S to save document..."
    try {
        Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "ctrl+s"} | Out-Null
        Start-Sleep -Seconds 3
        Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "return"} | Out-Null
        Start-Sleep -Seconds 2
    } catch {
        Write-Host "WARNING: Could not send Ctrl+S: $($_.Exception.Message)"
    }

    # Collect file metadata for both possible output files
    $outputFile = "C:\Users\Docker\Desktop\WordTasks\patent_license_final.docx"
    $draftFile  = "C:\Users\Docker\Desktop\WordTasks\patent_license_draft_tracked.docx"

    $fileInfo = [ordered]@{
        final_exists   = $false
        final_size     = 0
        final_mtime    = 0
        final_is_new   = $false
        draft_mtime    = 0
    }

    if (Test-Path $outputFile) {
        $fi = Get-Item $outputFile
        $mtime = [int][DateTimeOffset]::new($fi.LastWriteTimeUtc).ToUnixTimeSeconds()
        $fileInfo.final_exists = $true
        $fileInfo.final_size   = $fi.Length
        $fileInfo.final_mtime  = $mtime
        $fileInfo.final_is_new = ($mtime -gt $taskStartUnix)
        Write-Host "Final file: $outputFile (mtime=$mtime, is_new=$($fileInfo.final_is_new))"
    } else {
        Write-Host "Final file not found: $outputFile"
    }

    if (Test-Path $draftFile) {
        $fi2 = Get-Item $draftFile
        $fileInfo.draft_mtime = [int][DateTimeOffset]::new($fi2.LastWriteTimeUtc).ToUnixTimeSeconds()
    }

    $result = [ordered]@{
        task_start_unix = $taskStartUnix
        output_file     = $fileInfo
    }

    $resultPath = "C:\Users\Docker\contract_amendment_track_changes_result.json"
    $result | ConvertTo-Json -Depth 5 | Out-File -FilePath $resultPath -Encoding UTF8 -Force
    Write-Host "Result written to: $resultPath"

    Write-Host "=== Export complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
