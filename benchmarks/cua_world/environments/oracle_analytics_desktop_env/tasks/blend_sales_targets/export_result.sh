# NOTE: This is actually a PowerShell script (export_result.ps1)
# Save as `export_result.ps1` for the Windows environment.

$ErrorActionPreference = "Continue"
Write-Host "=== Exporting Results ==="

# Paths
$DocPath = "C:\Users\Docker\Documents"
$DvaPath = "$DocPath\Regional_Performance.dva"
$TimestampPath = "$env:TEMP\task_start_time.txt"
$ResultJsonPath = "$env:TEMP\task_result.json"

# 1. Get Task Start Time
if (Test-Path $TimestampPath) {
    $StartTime = [int64](Get-Content $TimestampPath)
} else {
    $StartTime = 0
    Write-Warning "Start time not found."
}

# 2. Check Result File (.dva)
$Exists = $false
$CreatedDuringTask = $false
$Size = 0
$ModifiedTime = 0

if (Test-Path $DvaPath) {
    $Exists = $true
    $Item = Get-Item $DvaPath
    $Size = $Item.Length
    $ModifiedTime = [int64]($Item.LastWriteTime.ToUniversalTime() - [DateTime]::UnixEpoch).TotalSeconds
    
    # Verify file was modified AFTER task started
    if ($ModifiedTime -gt $StartTime) {
        $CreatedDuringTask = $true
    }
}

# 3. Check if App is Still Running
$AppRunning = [bool](Get-Process "Oracle Analytics Desktop" -ErrorAction SilentlyContinue)

# 4. Prepare Result JSON
$Result = @{
    output_exists = $Exists
    file_created_during_task = $CreatedDuringTask
    output_size_bytes = $Size
    last_modified_time = $ModifiedTime
    task_start_time = $StartTime
    app_running = $AppRunning
    dva_path = $DvaPath
}

# 5. Save JSON
$Result | ConvertTo-Json | Set-Content $ResultJsonPath
Write-Host "Result metadata saved to $ResultJsonPath"
Get-Content $ResultJsonPath

Write-Host "=== Export Complete ==="