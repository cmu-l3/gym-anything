# export_result.ps1 — insurance_loss_ratio_analysis
# Saves workbook, captures file metadata, writes result JSON for verifier.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$logPath    = "C:\Users\Docker\task_post_insurance_loss.log"
$resultPath = "C:\Users\Docker\task_result.json"
$startFile  = "C:\Users\Docker\task_start_ts_insurance_loss.txt"
$xlsxPath   = "C:\Users\Docker\Documents\pc_industry_ratios.xlsx"

try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting insurance_loss_ratio_analysis result ==="

    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (Test-Path $utils) { . $utils }

    # Read task start timestamp
    $taskStart = 0
    if (Test-Path $startFile) {
        $taskStart = [int](Get-Content $startFile -Raw).Trim()
    }
    Write-Host "Task start timestamp: $taskStart"

    # Send Ctrl+S to save the workbook
    try {
        Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "ctrl+s"} | Out-Null
        Start-Sleep -Seconds 3
        Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "return"} | Out-Null
        Start-Sleep -Seconds 2
        Write-Host "Ctrl+S sent via PyAutoGUI"
    } catch {
        Write-Host "WARNING: PyAutoGUI Ctrl+S failed: $($_.Exception.Message)"
    }

    # Helper: get file metadata and is_new flag
    function Get-FileResult {
        param([string]$FilePath)
        if (Test-Path $FilePath) {
            $fi    = Get-Item $FilePath
            $mtime = [int][DateTimeOffset]::new($fi.LastWriteTimeUtc).ToUnixTimeSeconds()
            return [ordered]@{
                exists     = $true
                size_bytes = [long]$fi.Length
                mtime_unix = $mtime
                is_new     = ($mtime -gt $taskStart)
            }
        }
        return [ordered]@{ exists = $false; size_bytes = 0; mtime_unix = 0; is_new = $false }
    }

    $xlsxInfo = Get-FileResult $xlsxPath
    Write-Host "xlsx exists=$($xlsxInfo.exists) is_new=$($xlsxInfo.is_new) size=$($xlsxInfo.size_bytes)"

    $result = [ordered]@{
        task       = "insurance_loss_ratio_analysis"
        task_start = $taskStart
        xlsx_file  = $xlsxInfo
    }

    $result | ConvertTo-Json -Depth 5 | Out-File -FilePath $resultPath -Encoding UTF8 -Force
    Write-Host "Result JSON written to: $resultPath"

    Write-Host "=== Export complete: insurance_loss_ratio_analysis ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
