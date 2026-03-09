# export_result.ps1 (Powershell)

Write-Host "=== Exporting Results ==="

$OutputPath = "C:\Users\Docker\Documents\annotated_case.vital"
$ResultJsonPath = "C:\Users\Docker\Documents\task_result.json"
$StartTimeFile = "C:\Users\Docker\Documents\task_start_time.txt"

# Get Task Start Time
if (Test-Path $StartTimeFile) {
    $StartTime = Get-Content $StartTimeFile
} else {
    $StartTime = 0
}

$OutputExists = $false
$FileCreatedDuringTask = $false
$FileSize = 0
$FileMTime = 0

# Check Output File
if (Test-Path $OutputPath) {
    $OutputExists = $true
    $Item = Get-Item $OutputPath
    $FileSize = $Item.Length
    
    # Get Unix Timestamp of LastWriteTime
    $FileMTime = [int][double]::Parse((Get-Date -Date $Item.LastWriteTime -UFormat %s))
    
    if ($FileMTime -gt $StartTime) {
        $FileCreatedDuringTask = $true
    }
}

# Check if App is Running
$AppRunning = [bool](Get-Process "VitalRecorder" -ErrorAction SilentlyContinue)

# Create JSON Object
$Result = @{
    task_start = [int]$StartTime
    task_end = [int][double]::Parse((Get-Date -UFormat %s))
    output_exists = $OutputExists
    file_created_during_task = $FileCreatedDuringTask
    output_size_bytes = $FileSize
    app_was_running = $AppRunning
    output_path = $OutputPath
}

# Convert to JSON and Save
$Result | ConvertTo-Json | Set-Content $ResultJsonPath

Write-Host "Result exported to $ResultJsonPath"
Get-Content $ResultJsonPath