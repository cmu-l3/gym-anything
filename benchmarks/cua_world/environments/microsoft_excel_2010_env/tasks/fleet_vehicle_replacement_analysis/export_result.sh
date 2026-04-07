# Note: This file is named .sh for framework consistency, but strictly contains PowerShell code
# meant to be executed via the 'post_task' hook command specified in task.json.
# In a real deployment, this would be saved as export_result.ps1.

$ErrorActionPreference = "Continue"
Write-Host "=== Exporting Task Results ==="

$ResultFile = "C:\workspace\tasks\fleet_vehicle_replacement_analysis\task_result.json"
$ExcelPath = "C:\Users\Docker\Documents\fleet_analysis.xlsx"
$TaskStartPath = "C:\workspace\tasks\fleet_vehicle_replacement_analysis\task_start_time.txt"

# Get timestamps
$TaskEnd = [int][double]::Parse((Get-Date -UFormat %s))
if (Test-Path $TaskStartPath) {
    $TaskStart = Get-Content $TaskStartPath
} else {
    $TaskStart = 0
}

# Check file status
$FileExists = $false
$FileModified = $false
$FileSize = 0

if (Test-Path $ExcelPath) {
    $FileExists = $true
    $Item = Get-Item $ExcelPath
    $FileSize = $Item.Length
    
    # Convert LastWriteTime to Unix timestamp
    $WriteTime = [int][double]::Parse((Get-Date -Date $Item.LastWriteTime -UFormat %s))
    
    if ($WriteTime -gt $TaskStart) {
        $FileModified = $true
    }
}

# Check if Excel is still running
$AppRunning = [bool](Get-Process excel -ErrorAction SilentlyContinue)

# Create JSON Result
$JsonContent = @{
    task_start = $TaskStart
    task_end = $TaskEnd
    output_exists = $FileExists
    file_modified_during_task = $FileModified
    output_size_bytes = $FileSize
    app_was_running = $AppRunning
    output_path = $ExcelPath
} | ConvertTo-Json

$JsonContent | Out-File $ResultFile -Encoding ascii

Write-Host "Result exported to $ResultFile"
Get-Content $ResultFile