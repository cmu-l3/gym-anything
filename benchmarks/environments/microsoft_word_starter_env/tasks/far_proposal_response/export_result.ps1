# Export result for far_proposal_response task.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$logPath = "C:\Users\Docker\task_post_task_far_proposal_response.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Exporting far_proposal_response result ==="

    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) { throw "Missing task utils: $utils" }
    . $utils

    $timestampFile = "C:\Users\Docker\task_start_far_proposal_response.txt"
    $taskStartUnix = 0
    if (Test-Path $timestampFile) {
        $taskStartUnix = [int](Get-Content $timestampFile -Raw).Trim()
    }

    Write-Host "Sending Ctrl+S..."
    try {
        Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "ctrl+s"} | Out-Null
        Start-Sleep -Seconds 3
        Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "return"} | Out-Null
        Start-Sleep -Seconds 2
    } catch {
        Write-Host "WARNING: Could not send Ctrl+S: $($_.Exception.Message)"
    }

    $outputFile = "C:\Users\Docker\Desktop\WordTasks\mssoc_proposal_response.docx"
    $fileInfo = [ordered]@{
        final_exists = $false
        final_size   = 0
        final_mtime  = 0
        final_is_new = $false
    }

    if (Test-Path $outputFile) {
        $fi = Get-Item $outputFile
        $mtime = [int][DateTimeOffset]::new($fi.LastWriteTimeUtc).ToUnixTimeSeconds()
        $fileInfo.final_exists = $true
        $fileInfo.final_size   = $fi.Length
        $fileInfo.final_mtime  = $mtime
        $fileInfo.final_is_new = ($mtime -gt $taskStartUnix)
        Write-Host "Final file mtime=$mtime, is_new=$($fileInfo.final_is_new)"
    }

    $result = [ordered]@{ task_start_unix = $taskStartUnix; output_file = $fileInfo }
    $resultPath = "C:\Users\Docker\far_proposal_response_result.json"
    $result | ConvertTo-Json -Depth 5 | Out-File -FilePath $resultPath -Encoding UTF8 -Force
    Write-Host "Result written to: $resultPath"

    Write-Host "=== Export complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
