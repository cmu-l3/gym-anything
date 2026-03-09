# Note: This file is named .sh but contains PowerShell content as per environment requirement
# It should be saved as export_result.ps1 in the environment
Write-Host "=== Exporting task results ==="

$OutputPath = "C:\Users\Docker\Documents\VitalRecorder\engineering_data.mat"
$ResultJsonPath = "C:\tmp\task_result.json"
$StartTimePath = "C:\tmp\task_start_time.txt"

# 1. Get Task Start Time
if (Test-Path $StartTimePath) {
    $StartTime = [long](Get-Content $StartTimePath)
} else {
    $StartTime = 0
}

# 2. Check Output File
$FileExists = $false
$FileSize = 0
$FileCreatedDuringTask = $false
$FileMTime = 0

if (Test-Path $OutputPath) {
    $Item = Get-Item $OutputPath
    $FileExists = $true
    $FileSize = $Item.Length
    
    # Get Unix timestamp for modification time
    $FileMTime = [DateTimeOffset]::new($Item.LastWriteTime).ToUnixTimeSeconds()
    
    if ($FileMTime -ge $StartTime) {
        $FileCreatedDuringTask = $true
    }
}

# 3. Check Application State
$AppRunning = [bool](Get-Process VitalRecorder -ErrorAction SilentlyContinue)

# 4. Create JSON Result
$JsonContent = @{
    output_exists = $FileExists
    output_path = $OutputPath
    output_size_bytes = $FileSize
    file_created_during_task = $FileCreatedDuringTask
    file_mtime = $FileMTime
    task_start_time = $StartTime
    app_was_running = $AppRunning
    timestamp = [DateTimeOffset]::Now.ToUnixTimeSeconds()
} | ConvertTo-Json

Set-Content -Path $ResultJsonPath -Value $JsonContent

Write-Host "Result exported to $ResultJsonPath"
Get-Content $ResultJsonPath
Write-Host "=== Export complete ==="