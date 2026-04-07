# PowerShell script saved as export_result.ps1 in the environment
$ErrorActionPreference = "Continue"

Write-Host "=== Exporting Result ==="

$resultPath = "C:\tmp\task_result.json"
$targetFile = "C:\Users\Docker\Documents\commercial_circuits.xlsx"
$startTimeFile = "C:\tmp\task_start_time.txt"

# 1. Check if Excel is running
$excelRunning = (Get-Process "EXCEL" -ErrorAction SilentlyContinue)
$isExcelRunning = [bool]$excelRunning

# 2. Check File Stats
$fileExists = Test-Path $targetFile
$fileSize = 0
$fileModified = $false

if ($fileExists) {
    $item = Get-Item $targetFile
    $fileSize = $item.Length
    $lastWriteTime = $item.LastWriteTime
    
    if (Test-Path $startTimeFile) {
        $startTimeStr = Get-Content $startTimeFile
        $startTime = [DateTime]::ParseExact($startTimeStr, "yyyy-MM-dd HH:mm:ss", $null)
        if ($lastWriteTime -gt $startTime) {
            $fileModified = $true
        }
    }
}

# 3. Create JSON Result
$json = @{
    "excel_running" = $isExcelRunning
    "file_exists" = $fileExists
    "file_size" = $fileSize
    "file_modified" = $fileModified
    "timestamp" = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
}

$json | ConvertTo-Json | Out-File $resultPath -Encoding ascii

# 4. Take Screenshot (using nircmd if available or standard print screen method)
# This environment typically handles screenshots externally via the gym wrapper, 
# but we can try to save one if tools exist.
# Assuming standard gym environment handles visual capture.

Write-Host "Result exported to $resultPath"
Type $resultPath